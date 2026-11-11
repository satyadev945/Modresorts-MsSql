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

// Stateless bean: no in-memory state is held per instance. Shared state (cache) is externalized
// to Redis (e.g. Amazon ElastiCache) configured via REDIS_HOST / REDIS_PORT so all pod replicas share it.
@Stateless
public class ModResortsCustomerInformation {
  private static final String SELECT_CUSTOMERS_QUERY = "SELECT INFO FROM CUSTOMER";
  private static final String CACHE_KEY = "modresorts:customerInformation";
  private static final int CACHE_TTL_SECONDS = 300;

  // Removing DB connection for ease of demo setup
  // @Resource(lookup = "jdbc/ModResortsJndi")
  private DataSource dataSource;

  private Jedis connectToRedis() {
    String host = System.getenv("REDIS_HOST");
    if (host == null || host.isEmpty()) {
      return null;
    }
    String port = System.getenv("REDIS_PORT");
    try {
      Jedis jedis = new Jedis(host, port == null || port.isEmpty() ? 6379 : Integer.parseInt(port));
      String password = System.getenv("REDIS_PASSWORD");
      if (password != null && !password.isEmpty()) {
        jedis.auth(password);
      }
      return jedis;
    } catch (RuntimeException e) {
      e.printStackTrace();
      return null;
    }
  }

  public ArrayList<String> getCustomerInformation() {
    // Check the shared Redis cache first
    try (Jedis jedis = connectToRedis()) {
      if (jedis != null) {
        String cached = jedis.get(CACHE_KEY);
        if (cached != null) {
          return new ArrayList<>(Arrays.asList(cached.split("\\n")));
        }
      }
    } catch (RuntimeException e) {
      e.printStackTrace();
    }

    ArrayList<String> result = queryCustomerInformation();

    try (Jedis jedis = connectToRedis()) {
      if (jedis != null && !result.isEmpty()) {
        jedis.setex(CACHE_KEY, CACHE_TTL_SECONDS, String.join("\n", result));
      }
    } catch (RuntimeException e) {
      e.printStackTrace();
    }
    return result;
  }

  private ArrayList<String> queryCustomerInformation() {
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