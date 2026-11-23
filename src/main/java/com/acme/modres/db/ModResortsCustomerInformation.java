package com.acme.modres.db;

import javax.annotation.Resource;
import javax.ejb.Stateless;
import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

import redis.clients.jedis.Jedis;

// Stateless: shared state is externalized to Redis (ElastiCache) via REDIS_HOST/REDIS_PORT
@Stateless
public class ModResortsCustomerInformation {
  private static final String SELECT_CUSTOMERS_QUERY = "SELECT INFO FROM CUSTOMER";

  private static final String CACHE_KEY = "modres:customerInfo";
  private static final int CACHE_TTL_SECONDS = 300;
  private static final String REDIS_HOST = System.getenv("REDIS_HOST");
  private static final int REDIS_PORT = Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6379"));

  // Removing DB connection for ease of demo setup
  // @Resource(lookup = "jdbc/ModResortsJndi")
  private DataSource dataSource;

  public ArrayList<String> getCustomerInformation() {
    ArrayList<String> cached = readFromCache();
    if (cached != null) {
      return cached;
    }
    ArrayList<String> result = loadFromDatabase();
    writeToCache(result);
    return result;
  }

  private ArrayList<String> readFromCache() {
    if (REDIS_HOST == null || REDIS_HOST.isEmpty()) {
      return null;
    }
    try (Jedis jedis = new Jedis(REDIS_HOST, REDIS_PORT)) {
      List<String> values = jedis.lrange(CACHE_KEY, 0, -1);
      return (values == null || values.isEmpty()) ? null : new ArrayList<>(values);
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

  private void writeToCache(ArrayList<String> values) {
    if (REDIS_HOST == null || REDIS_HOST.isEmpty() || values == null || values.isEmpty()) {
      return;
    }
    try (Jedis jedis = new Jedis(REDIS_HOST, REDIS_PORT)) {
      jedis.del(CACHE_KEY);
      jedis.rpush(CACHE_KEY, values.toArray(new String[0]));
      jedis.expire(CACHE_KEY, CACHE_TTL_SECONDS);
    } catch (Exception e) {
      e.printStackTrace();
    }
  }

  private ArrayList<String> loadFromDatabase() {
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