--SELECTS THE DATABASE OF THE CLIENT AND CHECKS IF THE USERS ADMIN AND READONLY EXIST, IF NOT CREATES THEM.

IF NOT EXISTS 
    (SELECT name FROM sys.sysusers WHERE name = '#{adminUser-DB}#')
BEGIN
    CREATE USER "#{adminUser-DB}#" FROM LOGIN "#{adminLogin-DB}#";
    ALTER ROLE db_owner ADD MEMBER "#{adminUser-DB}#";
END

IF NOT EXISTS 
    (SELECT name FROM sys.sysusers WHERE name = '#{readUser-DB}#')
BEGIN
    CREATE USER "#{readUser-DB}#" FROM LOGIN "#{readLogin-DB}#";
    ALTER ROLE db_datareader ADD MEMBER "#{readUser-DB}#";
END