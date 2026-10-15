--[=[
	A compression library fully written in lua so that you don't have to rely on inconsistent implementations of lz4.
	@class Flate
]=]
local Vec = require("./vec")
local Flate = {}

local MAGIC_NUMBER = 0x184D2204
local BLOCK_MAX_SIZE = 65536
-- the frame descriptor is always FLG 0x60 and BD 0x40, so its checksum is always the same
local FLG = 0x60
local BD = 0x40
local HEADER_CHECKSUM = 0x82
-- the LZ4 block format requires the last 5 bytes of a block to be literals
local LAST_LITERALS = 5

-- Knuth multiplicative hash of 4 bytes to 16 bits. The product of two 32-bit numbers does not fit in a double,
-- so the function multiplies the low and the high 16 bits separately and keeps the result modulo 2^32.
local function hash(v: number): number
	local product = bit32.band(v, 0xFFFF) * 2654435761 + bit32.lshift(bit32.rshift(v, 16) * 2654435761 % 0x10000, 16)
	return bit32.rshift(product % 0x100000000, 16)
end

local function compressBlock(src: Vec.Vec, startPos: number, len: number): Vec.Vec
	local out = Vec.New()
	if len == 0 then
		out:Append(8, 0)
		return out
	end

	if len < 13 then
		local token = bit32.lshift(math.min(len, 15), 4)
		out:Append(8, token)
		if len >= 15 then
			local remaining = len - 15
			while remaining >= 255 do
				out:Append(8, 255)
				remaining -= 255
			end
			out:Append(8, remaining)
		end
		local outPos = out.length // 8
		out:_ensure(outPos + len)
		buffer.copy(out.inner, outPos, src.inner, startPos, len)
		out:_use((outPos + len) * 8)
		return out
	end

	local hashTable = {}
	local pos = 0
	local anchor = 0

	while pos <= len - 12 do
		local v = buffer.readu32(src.inner, startPos + pos)
		local h = hash(v)
		local ref = hashTable[h]
		hashTable[h] = pos

		if ref and ref < pos and (pos - ref) <= 65535 then
			local matchLen = 0
			while
				pos + matchLen < len - LAST_LITERALS
				and buffer.readu8(src.inner, startPos + pos + matchLen) == buffer.readu8(src.inner, startPos + ref + matchLen)
			do
				matchLen += 1
			end

			if matchLen >= 4 then
				local literalLen = pos - anchor
				local token = bit32.lshift(math.min(literalLen, 15), 4)
				local ml = matchLen - 4
				token = bit32.bor(token, math.min(ml, 15))
				out:Append(8, token)

				if literalLen >= 15 then
					local remaining = literalLen - 15
					while remaining >= 255 do
						out:Append(8, 255)
						remaining -= 255
					end
					out:Append(8, remaining)
				end

				if literalLen > 0 then
					local outPos = out.length // 8
					out:_ensure(outPos + literalLen)
					buffer.copy(out.inner, outPos, src.inner, startPos + anchor, literalLen)
					out:_use((outPos + literalLen) * 8)
				end

				out:Append(16, pos - ref)

				if ml >= 15 then
					local remaining = ml - 15
					while remaining >= 255 do
						out:Append(8, 255)
						remaining -= 255
					end
					out:Append(8, remaining)
				end

				pos += matchLen
				anchor = pos
			else
				pos += 1
			end
		else
			pos += 1
		end
	end

	local literalLen = len - anchor
	local token = bit32.lshift(math.min(literalLen, 15), 4)
	out:Append(8, token)

	if literalLen >= 15 then
		local remaining = literalLen - 15
		while remaining >= 255 do
			out:Append(8, 255)
			remaining -= 255
		end
		out:Append(8, remaining)
	end

	if literalLen > 0 then
		local outPos = out.length // 8
		out:_ensure(outPos + literalLen)
		buffer.copy(out.inner, outPos, src.inner, startPos + anchor, literalLen)
		out:_use((outPos + literalLen) * 8)
	end

	return out
end

local function decompressBlock(src: Vec.Vec, startPos: number, blockSize: number, out: Vec.Vec)
	local pos = 0
	local len = blockSize

	while pos < len do
		local token = buffer.readu8(src.inner, startPos + pos)
		pos += 1

		local literalLen = bit32.rshift(token, 4)
		if literalLen == 15 then
			repeat
				if pos >= len then
					error("Unexpected end of block")
				end
				local byte = buffer.readu8(src.inner, startPos + pos)
				pos += 1
				literalLen += byte
			until byte ~= 255
		end

		if literalLen > 0 then
			if pos + literalLen > len then
				error("Literal extends beyond input")
			end
			local outPos = out.length // 8
			out:_ensure(outPos + literalLen)
			buffer.copy(out.inner, outPos, src.inner, startPos + pos, literalLen)
			out:_use((outPos + literalLen) * 8)
			pos += literalLen
		end

		if pos >= len then
			break
		end

		if pos + 1 >= len then
			break
		end

		local offset = buffer.readu16(src.inner, startPos + pos)
		pos += 2

		local currentOutLen = out.length // 8
		if offset == 0 or offset > currentOutLen then
			error("Invalid offset: " .. offset)
		end

		local matchLen = bit32.band(token, 0x0F)
		if matchLen == 15 then
			repeat
				if pos >= len then
					error("Unexpected end of block")
				end
				local byte = buffer.readu8(src.inner, startPos + pos)
				pos += 1
				matchLen += byte
			until byte ~= 255
		end
		matchLen += 4

		local matchPos = currentOutLen - offset
		local outPos = currentOutLen
		out:_ensure(outPos + matchLen)
		if offset >= matchLen then
			buffer.copy(out.inner, outPos, out.inner, matchPos, matchLen)
		else
			for i = 0, matchLen - 1 do
				buffer.writeu8(out.inner, outPos + i, buffer.readu8(out.inner, matchPos + (i % offset)))
			end
		end
		out:_use((outPos + matchLen) * 8)
	end
end

--[=[
	Compresses the input into the LZ4 frame format.

	@param input string -- The input data to be compressed
	@return string -- The output data compressed into the lz4 file format
]=]
function Flate.Compress(input: string): string
	local src = Vec.FromString(input)
	local srcLen = src.length // 8
	local dest = Vec.New()

	dest:Append(32, MAGIC_NUMBER)
	dest:Append(8, FLG)
	dest:Append(8, BD)
	dest:Append(8, HEADER_CHECKSUM)

	local srcPos = 0
	while srcPos < srcLen do
		local blockSize = math.min(BLOCK_MAX_SIZE, srcLen - srcPos)
		local compVec = compressBlock(src, srcPos, blockSize)
		local compLen = compVec.length // 8

		if compLen < blockSize then
			dest:Append(32, compLen)
			local destPos = dest.length // 8
			dest:_ensure(destPos + compLen)
			buffer.copy(dest.inner, destPos, compVec.inner, 0, compLen)
			dest:_use((destPos + compLen) * 8)
		else
			dest:Append(32, bit32.bor(blockSize, 0x80000000))
			local destPos = dest.length // 8
			dest:_ensure(destPos + blockSize)
			buffer.copy(dest.inner, destPos, src.inner, srcPos, blockSize)
			dest:_use((destPos + blockSize) * 8)
		end

		srcPos += blockSize
	end

	dest:Append(32, 0)
	return dest:ToString()
end

--[=[
	Decompresses a valid LZ4 frame. The function skips checksums and does not verify them.
	It does not support dictionaries, skippable frames or more than one frame in the input.

	@param input string -- The lz4 compressed data to be decompressed
	@return string -- The decompressed data
	@error "Invalid LZ4 frame: bad magic number" | "Invalid LZ4 frame: header too short" | "Invalid LZ4 frame: unsupported version" | "Invalid LZ4 frame: dictionaries are not supported" | "Unexpected end of block" | "Literal extends beyond input" | "Invalid offset: {offset}" -- Throws when an invalid input has been passed
]=]
function Flate.Decompress(input: string): string
	local src = Vec.FromString(input)
	local srcLen = src.length // 8
	local pos = 0
	local out = Vec.New()

	if srcLen < 7 then
		error("Invalid LZ4 frame: bad magic number")
	end

	local magic = buffer.readu32(src.inner, pos)
	pos += 4

	if magic ~= MAGIC_NUMBER then
		error("Invalid LZ4 frame: bad magic number")
	end

	local flg = buffer.readu8(src.inner, pos)
	if bit32.rshift(flg, 6) ~= 1 then
		error("Invalid LZ4 frame: unsupported version")
	end
	if bit32.band(flg, 0x01) ~= 0 then
		error("Invalid LZ4 frame: dictionaries are not supported")
	end
	local hasBlockChecksum = bit32.band(flg, 0x10) ~= 0
	local hasContentSize = bit32.band(flg, 0x08) ~= 0

	-- FLG, BD, the optional content size and the header checksum
	pos += 2 + (if hasContentSize then 8 else 0) + 1
	if pos > srcLen then
		error("Invalid LZ4 frame: header too short")
	end

	while pos < srcLen do
		if pos + 4 > srcLen then
			break
		end
		local blockSize = buffer.readu32(src.inner, pos)
		pos += 4

		if blockSize == 0 then
			break
		end

		local compressed = bit32.band(blockSize, 0x80000000) == 0
		blockSize = bit32.band(blockSize, 0x7FFFFFFF)
		if pos + blockSize > srcLen then
			error("Unexpected end of block")
		end

		if compressed then
			decompressBlock(src, pos, blockSize, out)
		else
			local outPos = out.length // 8
			out:_ensure(outPos + blockSize)
			buffer.copy(out.inner, outPos, src.inner, pos, blockSize)
			out:_use((outPos + blockSize) * 8)
		end

		pos += blockSize
		if hasBlockChecksum then
			pos += 4
		end
	end

	return out:ToString()
end

return Flate
