#!/bin/bash

#function to create and check if the password is correctly generated with the password policy for SQL Login and if the password has always a special character
createPassword () {
  randomPass="$(cat /dev/urandom | tr -c -d 'A-Za-z0-9_!|~@#$%^&*()[]+=' | head -c 14 )"
  while [[ ${#randomPass} -lt 8 || "$randomPass" != *[A-Z]* || "$randomPass" != *[a-z]* || "$randomPass" != *[0-9]* || "$randomPass" != *[\_\!\|\~\@\#\^\&\*\(\)\[\]\+]* ]];
  do
    randomPass="$(cat /dev/urandom | tr -c -d 'A-Za-z0-9_!|~@#$%^&*()[]+=' | head -c 14 )";
  done;
  echo $randomPass;    
}

export CLIENT_ADMINLOGINPWD_DB=$(createPassword)
export CLIENT_READLOGINPWD_DB=$(createPassword)
export CLIENT_RMQPWD=$(createPassword)
export CLIENT_VMPWD=$(createPassword)

echo "##vso[task.setvariable variable=CLIENT_ADMINLOGINPWD_DB]$CLIENT_ADMINLOGINPWD_DB"
echo "##vso[task.setvariable variable=CLIENT_READLOGINPWD_DB]$CLIENT_READLOGINPWD_DB"
echo "##vso[task.setvariable variable=CLIENT_RMQPWD]$CLIENT_RMQPWD"
echo "##vso[task.setvariable variable=CLIENT_VMPWD]$CLIENT_VMPWD"