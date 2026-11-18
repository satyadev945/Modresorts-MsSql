package com.acme.modres.db;

import javax.annotation.Resource;
import javax.ejb.Stateless;
import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Arrays;

import redis.clients.jedis.Jedis;

// Stateless bean: no instance-level state is held, so every pod replica behaves identically.
// Shared state (cached customer information) is externalized to Redis (e.g. Amazon ElastiCache).
@Stateless
public class ModResortsCustomerInformation {
  private static final String SELECT_CUSTOMERS_QUERY = "SELECT INFO FROM CUSTOMER";
  private static final String CACHE_KEY = "modresorts:customerInformation";
  private static final String CACHE_DELIMITER = "\u001F";
  private static final int CACHE_TTL_SECONDS = Integer
      .parseInt(System.getenv().getOrDefault("REDIS_CACHE_TTL_SECONDS", "60"));

  // Removing DB connection for ease of demo setup
  // @Resource(lookup = "jdbc/ModResortsJndi")
  private DataSource dataSource;

  private Jedis openRedis() {
    String host = System.getenv("REDIS_HOST");
    if (host == null || host.isEmpty()) {
      return null;
    }
    int port = Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6379"));
    Jedis jedis = new Jedis(host, port);
    String password = System.getenv("REDIS_PASSWORD");
    if (password != null && !password.isEmpty()) {
      jedis.auth(password);
    }
    return jedis;
  }

  public ArrayList<String> getCustomerInformation() {
    ArrayList<String> cached = readFromCache();
    if (cached != null) {
      return cached;
    }
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
    writeToCache(customerInfo);
    return customerInfo;
  }

  private ArrayList<String> readFromCache() {
    try (Jedis jedis = openRedis()) {
      if (jedis == null) {
        return null;
      }
      String value = jedis.get(CACHE_KEY);
      if (value == null) {
        return null;
      }
      return value.isEmpty() ? new ArrayList<>() : new ArrayList<>(Arrays.asList(value.split(CACHE_DELIMITER, -1)));
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

  private void writeToCache(ArrayList<String> customerInfo) {
    try (Jedis jedis = openRedis()) {
      if (jedis == null) {
        return;
      }
      jedis.setex(CACHE_KEY, CACHE_TTL_SECONDS, String.join(CACHE_DELIMITER, customerInfo));
    } catch (Exception e) {
      e.printStackTrace();
    }
  }
}