--[=[
	Manage data without any annoying folder checks!
	@class Path
]=]
local Path = {}

--[=[
	Ensures that a given folder path exists by creating any missing directories.
	@param folder string -- The folder path to assure
]=]
function Path.Assure(folder: string)
	local array = string.split(folder, "/")
	local current = ""

	for index, name in ipairs(array) do
		if index == 1 then
			current = name
		else
			current ..= "/" .. name
		end

		if not isfolder(current) then
			makefolder(current)
		end
	end
end

--[=[
	Writes data to a file at a specified path.

	@param value string -- The data to write
	@param name string -- The file name
	@param folder string? -- The folder path to store the data in. The default is 'Aria'.
]=]
function Path.Write(value: string, name: string, folder: string?)
	folder = folder and string.gsub(folder, "/+$", "") or "Aria"
	local path = `{folder}/{name}`

	Path.Assure(folder)
	writefile(path, value)
end

--[=[
	Retrieves from a file at a specified path.

	@param name string -- The file name.
	@param folder string? -- The folder path where the data is stored. The default is 'Aria'.
	@return string? -- The cached data, or nil if not found.
]=]
function Path.Read(name: string, folder: string?): string?
	folder = folder and string.gsub(folder, "/+$", "") or "Aria"
	local path = `{folder}/{name}`

	local success, result = pcall(readfile, path)
	if success then
		return result
	end
end

return Path
