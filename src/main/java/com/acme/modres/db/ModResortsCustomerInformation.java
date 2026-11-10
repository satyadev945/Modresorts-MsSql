package com.acme.modres.db;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;

@Service
public class ModResortsCustomerInformation {
  private static final String SELECT_CUSTOMERS_QUERY = "SELECT INFO FROM CUSTOMER";

  // DataSource (e.g. HikariCP pointing at AWS RDS) is supplied by Spring; optional for demo setup
  @Autowired(required = false)
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