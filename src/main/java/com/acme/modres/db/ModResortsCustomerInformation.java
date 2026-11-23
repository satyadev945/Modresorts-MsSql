package com.acme.modres.db;

import javax.annotation.Resource;
import javax.enterprise.context.Dependent;
import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;

// Stateless, per-injection bean (no singleton-held state); any shared/cached state must be
// externalized to Redis (e.g. ElastiCache) rather than held in this instance.
@Dependent
public class ModResortsCustomerInformation {
  private static final String SELECT_CUSTOMERS_QUERY = "SELECT INFO FROM CUSTOMER";

  // Removing DB connection for ease of demo setup
  // @Resource(lookup = "jdbc/ModResortsJndi")
  private DataSource dataSource;

  public ArrayList<String> getCustomerInformation() {
    Connection conn = null;
    PreparedStatement stmt = null;
    ResultSet rs = null;
    ArrayList<String> customerInfo = new ArrayList<>();

    try {
      // Get a connection from the injected data source
      conn = dataSource.getConnection();
      // Create a prepared statement
      stmt = conn.prepareStatement(SELECT_CUSTOMERS_QUERY);
      // Execute the query
      rs = stmt.executeQuery();

      // Process the results
      while (rs.next()) {
        String info = rs.getString("INFO");
        customerInfo.add(info);
      }

    } catch (SQLException e) {
      e.printStackTrace();
    } finally {
      // Close the result set, statement, and connection
      try {
        if (rs != null)
          rs.close();
        if (stmt != null)
          stmt.close();
        if (conn != null)
          conn.close();
      } catch (SQLException e) {
        e.printStackTrace();
      }
    }
    return customerInfo;
  }
}