-- Compatibility tombstone. Never activate, recover or execute cached updates.
return {removed=true,startup=function() return false end}
