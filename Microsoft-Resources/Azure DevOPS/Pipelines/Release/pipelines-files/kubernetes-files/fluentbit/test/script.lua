-- CRI output is supposed to put F on firstline of multiline and P on following line
-- It doesn't in Azure so we need to cleanup the output from CRI first before letting fluentbit merge multiline entries
function fix_cri(tag, timestamp, record)
  if record["log"] == nil then
    return 0, timestamp, record
  end
  log = record["log"]:gsub("\n[^\n]+ [FP] ", "\n")
  record["log"] = log
  return 1, timestamp, record
end

-- remove new line and carriage return
function remove_cr(tag, timestamp, record)
  if record["log"] == nil then
    return 0, timestamp, record
  end
  log = record["log"]:gsub("\n", "")
  log = record["log"]:gsub("\r", "")
  record["log"] = log
  return 1, timestamp, record
end

-- merge fields into one log message
function merge_logs(tag, timestamp, record)
  if record["log1"] == nil or record["log2"] == nil then
    return 0, timestamp, record
  end
  log = record["log1"] .. " " .. record["log2"]
	record["log1"] = nil
	record["log2"] = nil
  record["log"] = log
  return 1, timestamp, record
end

function record_date(tag, timestamp, record)
  new_record = record
  new_record["record_date"] = os.date("%Y-%m-%d",timestamp)
  return 1, timestamp, new_record
end

-- Print record to the standard output - use for debugging
function cb_print(tag, timestamp, record)
  output = tag .. ":  [" .. string.format("%f", timestamp) .. ", { "

  for key, val in pairs(record) do
     output = output .. string.format(" %s => %s,", key, val)
  end
  
  output = string.sub(output,1,-2) .. " }]"
  print(output)

  -- Record not modified so 'code' return value is 0 (first parameter)
  return 0, 0, 0
end