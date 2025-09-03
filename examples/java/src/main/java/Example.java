// see https://github.com/Microsoft/mssql-jdbc
import java.security.Provider;
import java.security.Security;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.Arrays;

public class Example {
    public static void main(String[] args) throws Exception {
        String[] securityProviders = Arrays.stream(Security.getProviders()).map(Provider::getName).toArray(String[]::new);
        System.out.printf("Java Security Providers: %s.%n", String.join(", ", securityProviders));

        String integratedSecurityConnectionString = String.format(
            "jdbc:sqlserver://%s:1433;database=master;integratedSecurity=true",
            System.getenv("SQL_SERVER_FQDN"));

        System.out.println("SQL Server Version:");
        System.out.println(queryScalar(integratedSecurityConnectionString, "select @@version"));

        System.out.println("SQL Server User Name (integrated authentication credentials; TCP/IP connection):");
        System.out.println(queryScalar(integratedSecurityConnectionString, "select suser_name()"));

        String connectionString = String.format(
            "jdbc:sqlserver://%s:1433;database=master;user=alice.doe;password=HeyH0Password",
            System.getenv("SQL_SERVER_FQDN"));

        System.out.println("SQL Server User Name (alice.doe; username/password credentials; TCP/IP connection):");
        System.out.println(queryScalar(connectionString, "select suser_name()"));

        System.out.println("Is this SQL Server connection encrypted? (alice.doe; username/password credentials; Encrypted TCP/IP connection):");
        System.out.println(queryScalar(connectionString + ";encrypt=strict", "select encrypt_option from sys.dm_exec_connections where session_id=@@SPID"));
    }

    private static String queryScalar(String connectionString, String sql) throws Exception {
        try (Connection connection = DriverManager.getConnection(connectionString)) {
            try (Statement statement = connection.createStatement()) {
                try (ResultSet resultSet = statement.executeQuery(sql)) {
                    if (resultSet.next()) {
                        return resultSet.getString(1);
                    }
                    return null;
                }
            }
        }
    }
}
