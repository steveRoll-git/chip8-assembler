function string.trim(str)
  return (str:gsub("^%s*", ""):gsub("%s*$", ""))
end

function string.split(inputstr, sep) -- https://stackoverflow.com/questions/1426954/split-string-in-lua#comment73602874_7615129
  local t={}
  if inputstr == "" then return t end
  for field,s in string.gmatch(inputstr, "([^"..sep.."]*)("..sep.."?)") do
    table.insert(t,field:trim())
    if s=="" then
      return t
    end
  end
end