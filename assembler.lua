local function trim(str)
  return (str:gsub("^%s*", ""):gsub("%s*$", ""))
end

local function split(inputstr, sep) -- https://stackoverflow.com/questions/1426954/split-string-in-lua#comment73602874_7615129
  local t={}
  if inputstr == "" then return t end
  for field,s in string.gmatch(inputstr, "([^"..sep.."]*)("..sep.."?)") do
    table.insert(t,trim(field))
    if s=="" then
      return t
    end
  end
end

local crlf = true

local bytes = string.char

local dummy2 = "\0\0"

local invalidNames = {["I"]=true, ["DT"]=true, ["ST"]=true}
for i=0, 0xF do
  invalidNames[("V%X"):format(i)] = true
end

local function parseV(str)
  if str:sub(1,1) == "V" and #str == 2 then
    return tonumber(str:sub(2), 16)
  end
end

local function twoBytes(total)
  return bytes(bit.band(bit.rshift(total, 8), 0xff), bit.band(total, 0xff))
end

local function assemble(code)
  if crlf then
    code = code:gsub("\r\n", "\n")
  end
  
  local lineNum = 1
  local function asmError(msg)
    error("assembly error line " .. lineNum .. ": " .. msg)
  end
  
  local function syntaxError()
    asmError("invalid syntax")
  end
  
  local function usageError(ins)
    asmError("invalid usage of instruction '" .. ins .. "'")
  end
  
  local function rangeError(name, value)
    asmError(("%s %d ($%X) is out of range"):format(name, value, value))
  end
  
  local function parseNumber(str)
    local num
    if str:sub(1,1) == "$" then
      num = tonumber(str:sub(2), 16)
    else
      num = tonumber(str)
    end
    
    if not num then
      asmError("invalid number '" .. str .. "'")
    end
    
    return num
  end
  
  local data = {}
  
  local currentAddr = 0x200
  
  local macros = {}
  local function transformString(s)
    for name, value in pairs(macros) do
      s = s:gsub(name, value)
    end
    return s
  end
  
  local symbols = {}
  
  local symbolRefs = {}
  
  local function refSymbol(name, fun)
    if invalidNames[name] then
      asmError("invalid symbol name '" .. name .. "'")
    end
    if symbols[name] then
      fun(symbols[name])
    else
      if not symbolRefs[name] then
        symbolRefs[name] = {}
      end
      table.insert(symbolRefs[name], {fun=fun, line=lineNum})
    end
  end
  
  local function addSymbol(name, value)
    if invalidNames[name] then
      asmError("invalid symbol name '" .. name .. "'")
    end
    if symbols[name] then
      asmError("symbol '" .. name .. "' already defined")
    end
    if symbolRefs[name] then
      for _, ref in ipairs(symbolRefs[name]) do
        ref.fun(value)
      end
      symbolRefs[name] = nil
    end
    symbols[name] = value
    
    --print("symbol '" .. name .. "' is '" .. value .. "'")
  end
  
  local function refNumber(value, onRef)
    if value:sub(1,1) == "$" or value:find("%d") == 1 then
      onRef(parseNumber(value))
    else
      refSymbol(value, onRef)
    end
  end
  
  local function addData(s)
    table.insert(data, s)
    currentAddr = currentAddr + #s
    
    return #data
  end
  
  local instructions = {
    
    CLS = function(args)
      if #args ~= 0 then usageError("cls") end
      
      addData(bytes(0x00, 0xE0))
    end,
    
    RET = function(args)
      if #args ~= 0 then usageError("ret") end
      
      addData(bytes(0x00, 0xEE))
    end,
    
    JP = function(args)
      if #args ~= 1 then usageError("jp") end
      
      local arg = args[1]
      
      local firstNib = 0x1
      local address = arg
      
      if arg:find("+") then
        local V, addr = unpack(split(arg, "+"))
        if addr == "V0" then
          V, addr = addr, V
        end
        
        if V ~= "V0" then
          usageError("jp")
        end
        
        firstNib = 0xB
        address = addr
      end
      
      local index = addData(dummy2)
      
      refNumber(address, function(value)
          if value < 0 or value > 0xfff then
            rangeError("jump address", value)
          end
          
          data[index] = twoBytes(bit.lshift(firstNib, 12) + value)
        end
      )
    end,
    
    CALL = function(args)
      if #args ~= 1 then usageError("jp") end
      
      local index = addData(dummy2)
      
      refNumber(args[1], function(value)
          if value < 0 or value > 0xfff then
            rangeError("call address", value)
          end
          
          data[index] = twoBytes(0x2000 + value)
        end
      )
    end,
    
    SE = function(args)
      if #args ~= 2 then usageError("se") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("se") end
      
      local Vy = parseV(args[2])
      if Vy then
        addData(bytes(0x50 + Vx, bit.lshift(Vy, 4)))
      else
        local index = addData(dummy2)
        
        refNumber(args[2], function(value)
            if value < 0 or value > 0xff then
              rangeError("comparison value", value)
            end
            
            data[index] = bytes(0x30 + Vx, value)
          end
        )
      end
    end,
    
    SNE = function(args)
      if #args ~= 2 then usageError("sne") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("sne") end
      
      local Vy = parseV(args[2])
      if Vy then
        addData(bytes(0x90 + Vx, bit.lshift(Vy, 4)))
      else
        local index = addData(dummy2)
        
        refNumber(args[2], function(value)
            if value < 0 or value > 0xff then
              rangeError("comparison value", value)
            end
            
            data[index] = bytes(0x40 + Vx, value)
          end
        )
      end
    end,
    
    LD = function(args)
      if #args ~= 2 then usageError("ld") end
      
      local Vx = parseV(args[1])
      
      if Vx then
        
        local Vy = parseV(args[2])
        if Vy then
          addData(bytes(0x80 + Vx, bit.lshift(Vy, 4)))
          
        elseif args[2] == "DT" then
          addData(bytes(0xF0 + Vx, 0x07))
          
        elseif args[2] == "[I]" then
          addData(bytes(0xF0 + Vx, 0x65))
          
        else
          local index = addData(dummy2)
          
          refNumber(args[2], function(value)
              if value < 0 or value > 0xff then
                rangeError("V value", value)
              end
              
              data[index] = bytes(0x60 + Vx, value)
            end
          )
          
        end
        
      elseif args[1] == "I" then
        local index = addData(dummy2)
        
        refNumber(args[2], function(value)
            if value < 0 or value > 0xfff then
              rangeError("I value", value)
            end
            
            data[index] = twoBytes(0xA000 + value)
          end
        )
        
      elseif args[1] == "DT" then
        local Vx = parseV(args[2])
        if not Vx then usageError("ld") end
        
        addData(bytes(0xF0 + Vx, 0x15))
        
      elseif args[1] == "ST" then
        local Vx = parseV(args[2])
        if not Vx then usageError("ld") end
        
        addData(bytes(0xF0 + Vx, 0x18))
        
      elseif args[1] == "[I]" then
        local Vx = parseV(args[2])
        if not Vx then usageError("ld") end
        
        addData(bytes(0xF0 + Vx, 0x55))
        
      else
        usageError("ld")
      end
    end,
    
    ADD = function(args)
      if #args ~= 2 then usageError("add") end
      
      if args[1] == "I" then
        local Vx = parseV(args[2])
        if not Vx then usageError("add") end
        
        addData(bytes(0xF0 + Vx, 0x1E))
      else
        local Vx = parseV(args[1])
        if not Vx then usageError("add") end
        
        local Vy = parseV(args[2])
        if Vy then
          addData(bytes(0x80 + Vx, bit.lshift(Vy, 4) + 0x04))
          
        else
          local index = addData(dummy2)
          
          refNumber(args[2], function(value)
              if value < 0 or value > 0xff then
                rangeError("V addition", value)
              end
              
              data[index] = bytes(0x70 + Vx, value)
            end
          )
          
        end
      end
    end,
    
    SUB = function(args)
      if #args ~= 2 then usageError("sub") end
      
      local Vx, Vy = parseV(args[1]), parseV(args[2])
      if not Vx or not Vy then usageError("sub") end
      
      addData(bytes(0x80 + Vx, bit.lshift(Vy, 4) + 0x05))
    end,
    
    SUBN = function(args)
      if #args ~= 2 then usageError("subn") end
      
      local Vx, Vy = parseV(args[1]), parseV(args[2])
      if not Vx or not Vy then usageError("subn") end
      
      addData(bytes(0x80 + Vx, bit.lshift(Vy, 4) + 0x07))
    end,
    
    SHR = function(args)
      if #args ~= 1 and #args ~= 2 then usageError("shl") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("shr") end
      
      local Vy = not args[2] and Vx or parseV(args[2])
      if args[2] and not Vy then usageError("shr") end
      
      addData(bytes(0x80 + Vx, bit.lshift(Vy, 4) + 0x06))
    end,
    
    SHL = function(args)
      if #args ~= 1 and #args ~= 2 then usageError("shl") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("shl") end
      
      local Vy = not args[2] and Vx or parseV(args[2])
      if args[2] and not Vy then usageError("shl") end
      
      addData(bytes(0x80 + Vx, bit.lshift(Vy, 4) + 0x0E))
    end,
    
    OR = function(args)
      if #args ~= 2 then usageError("or") end
      
      local Vx, Vy = parseV(args[1]), parseV(args[2])
      if not Vx or not Vy then usageError("or") end
      
      addData(bytes(0x80 + Vx, bit.lshift(Vy, 4) + 0x01))
    end,
    
    AND = function(args)
      if #args ~= 2 then usageError("and") end
      
      local Vx, Vy = parseV(args[1]), parseV(args[2])
      if not Vx or not Vy then usageError("and") end
      
      addData(bytes(0x80 + Vx, bit.lshift(Vy, 4) + 0x02))
    end,
    
    XOR = function(args)
      if #args ~= 2 then usageError("xor") end
      
      local Vx, Vy = parseV(args[1]), parseV(args[2])
      if not Vx or not Vy then usageError("xor") end
      
      addData(bytes(0x80 + Vx, bit.lshift(Vy, 4) + 0x03))
    end,
    
    RND = function(args)
      if #args ~= 1 and #args ~= 2 then usageError("rnd") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("rnd") end
      
      if args[2] then
        local index = addData(dummy2)
        
        refNumber(args[2], function(value)
            if value < 0 or value > 0xff then
              rangeError("RND parameter", value)
            end
            
            data[index] = bytes(0xC0 + Vx, value)
          end
        )
      else
        addData(bytes(0xC0 + Vx, 0xFF))
      end
      
    end,
    
    DRW = function(args)
      if #args ~= 3 then usageError("drw") end
      
      local Vx, Vy = parseV(args[1]), parseV(args[2])
      if not Vx or not Vy then usageError("drw") end
      
      local index = addData(dummy2)
      
      refNumber(args[3], function(value)
          if value < 0 or value > 0xf then
            rangeError("sprite height", value)
          end
          
          data[index] = bytes(0xD0 + Vx, bit.lshift(Vy, 4) + value)
        end
      )
    end,
    
    SKP = function(args)
      if #args ~= 1 then usageError("skp") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("skp") end
      
      addData(bytes(0xE0 + Vx, 0x9E))
    end,
    
    SKNP = function(args)
      if #args ~= 1 then usageError("sknp") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("sknp") end
      
      addData(bytes(0xE0 + Vx, 0xA1))
    end,
    
    KEY = function(args)
      if #args ~= 1 then usageError("key") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("key") end
      
      addData(bytes(0xF0 + Vx, 0x0A))
    end,
    
    HEX = function(args)
      if #args ~= 1 then usageError("hex") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("hex") end
      
      addData(bytes(0xF0 + Vx, 0x29))
    end,
    
    BCD = function(args)
      if #args ~= 1 then usageError("bcd") end
      
      local Vx = parseV(args[1])
      if not Vx then usageError("bcd") end
      
      addData(bytes(0xF0 + Vx, 0x33))
    end
  }
  
  for _, line in ipairs(split(code, "\n")) do
    line = trim(line)
    line = line:sub(1, (line:find(";") or 0) - 1)
    line = transformString(line)
    
    if #line > 0 then
      if line:sub(1,7) == "#define" then
        --define macro
        local _, spaceA = line:find("%s+")
        local spaceB, spaceC = line:find("%s+", spaceA + 1)
        
        local name = line:sub(spaceA + 1, spaceB - 1)
        local value = line:sub(spaceC + 1, line:find("%s", spaceC + 1))
        
        macros[name] = value
        
      elseif line:sub(1,1) == "." then
        --directive
        local space = line:find(" ")
        if not space then syntaxError() end
        local directive = line:sub(2, space - 1)
        local args = split(line:sub(space + 1), ",")
        
        if directive == "byte" then
          if #args < 1 then asmError("byte directive expected byte") end
          
          local data = ""
          
          for _, n in ipairs(args) do
            data = data .. bytes(parseNumber(n))
          end
          
          addData(data)
          
        elseif directive == "spriteImage" then
          if #args ~= 1 then asmError("spriteImage directive expected filename") end
          
          if not love.filesystem.getInfo(args[1]) then
            asmError("file '" .. args[1] .. "' not found")
          end
          
          local img = love.image.newImageData(args[1])
          if img:getWidth() > 8 or img:getHeight() > 15 then
            asmError("image too big (must be 8x15 or less)")
          end
          
          local imgBytes = ""
          for y=0, img:getHeight() - 1 do
            local num = 0
            local str = ""
            for x=0, img:getWidth() - 1 do
              str = str .. img:getPixel(x, y)
              num = num + 2 ^ (7 - x) * (img:getPixel(x, y) == 1 and 1 or 0)
            end
            imgBytes = imgBytes .. bytes(num)
          end
          addData(imgBytes)
          
        else
          asmError("unknown directive '" .. directive .. "'")
        end
        
      elseif line:find("=") then
        --symbol definition
        local eq = line:find("=")
        local name = trim(line:sub(1, eq - 1))
        local value = trim(line:sub(eq + 1))
        addSymbol(name, parseNumber(value))
        
      elseif line:find(":") then
        --label
        local colon = line:find(":")
        local name = trim(line:sub(1, colon - 1))
        addSymbol(name, currentAddr)
        
      else
        --instruction
        local spaceA, spaceB = line:find("%s+")
        spaceA = spaceA or (#line + 1)
        spaceB = spaceB or #line
        
        local instr = line:sub(1, spaceA - 1):upper()
        
        if not instructions[instr] then
          asmError("unknown instruction '" .. instr .. "'")
        end
        
        local args = split(line:sub(spaceB + 1), ",")
        
        instructions[instr](args)
        
      end
    end
    
    lineNum = lineNum + 1
  end
  
  if next(symbolRefs) then
    local err = "assembly error - unresolved symbols: "
    for n, refs in pairs(symbolRefs) do
      err = err .. "\n'" .. n .. "' (line" .. (#refs > 1 and "s " or " ")
      for i, r in ipairs(refs) do
        err = err .. r.line .. (i < #refs and ", " or "")
      end
      err = err .. ")"
    end
    error(err)
  end
  
  return table.concat(data)
end

return assemble