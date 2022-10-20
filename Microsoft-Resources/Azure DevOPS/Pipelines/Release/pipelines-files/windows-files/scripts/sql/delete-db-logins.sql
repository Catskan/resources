--CHECK IF THE LOGINS EXIST IN THE DATABASE SERVER, IF THEY EXIST, DELETES THEM

IF EXISTS
    (SELECT name FROM master.sys.sql_logins WHERE name = '#{adminLogin-DB}#')
BEGIN
    DROP LOGIN "#{adminLogin-DB}#";
    PRINT N'## Admin Login Deleted. ##';
END
ELSE
BEGIN
    PRINT N'## This Admin login has already been deleted. ##';
END

IF EXISTS
    (SELECT name FROM master.sys.sql_logins WHERE name = '#{readLogin-DB}#')
BEGIN
    DROP LOGIN "#{readLogin-DB}#";
    PRINT N'## Read Login Deleted ##';
END
ELSE
BEGIN
    PRINT N'## This Read login has already been deleted. ##';
END