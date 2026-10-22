--[=[
	Cache your data without any annoying folder checks!
	@class Cache
]=]
local Cache = {}
local data = {}

--[=[
	Ensures that a given folder path exists by creating any missing directories.
	@param folder string -- The folder path to assure
]=]
function Cache.Assure(folder: string)
	local array = string.split(folder, "/")
	local current = ""

	for index, name in ipairs(array) do
		current = current .. (if index == 1 then name else "/" .. name)

		if not isfolder(current) then
			makefolder(current)
		end
	end
end

--[=[
	Writes data to a file and stores it in an in-memory cache.

	@param value string -- The data to cache
	@param name string -- The name of the cached item/file
	@param folder string? -- The folder path to store the data in. The default is 'Aria/Cache'.
]=]
function Cache:To(value: string, name: string, folder: string?)
	folder = if folder then string.gsub(folder, "/+$", "") else "Aria/Cache"
	local path = folder .. "/" .. name

	Cache.Assure(folder)
	writefile(path, value)
	data[path] = value
end

--[=[
	Retrieves data from the in-memory cache or from a file if not present.

	@param name string -- The name of the cached item/file.
	@param folder string? -- The folder path where the data is stored. The default is 'Aria/Cache'.
	@return string? -- The cached data, or nil if not found.
]=]
function Cache:From(name: string, folder: string?): string?
	folder = if folder then string.gsub(folder, "/+$", "") else "Aria/Cache"
	local path = folder .. "/" .. name
	local cached = data[path]
	if cached then
		return cached
	end

	local success, result = pcall(readfile, path)
	if success then
		data[path] = result
		return result
	end
end

return Cache
