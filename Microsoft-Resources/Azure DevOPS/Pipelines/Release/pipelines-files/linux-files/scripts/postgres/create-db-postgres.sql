CREATE ROLE #{kcDBadminUser}# PASSWORD '#{kcDBadminPwd}#' LOGIN;
ALTER ROLE #{kcDBadminUser}# PASSWORD '#{kcDBadminPwd}#';
CREATE DATABASE #{kcDBname}#;
grant all privileges on database #{kcDBname}# to #{kcDBadminUser}#;
GRANT "#{kcDBadminUser}#" TO "#{kcPostgreSqlServerAdminLogin}#";
\q