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

// Stateless bean: no per-instance state is held; shared state lives in Redis (ElastiCache)
@Stateless
public class ModResortsCustomerInformation {
  private static final String SELECT_CUSTOMERS_QUERY = "SELECT INFO FROM CUSTOMER";

  // Removing DB connection for ease of demo setup
  // @Resource(lookup = "jdbc/ModResortsJndi")
  private DataSource dataSource;

  // Shared state externalized to Redis (ElastiCache) so all pod replicas see the same data
  private static final String REDIS_HOST = System.getenv().getOrDefault("REDIS_HOST", "localhost");
  private static final int REDIS_PORT = Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6379"));
  private static final String CACHE_KEY = "modres:customer-info";
  private static final int CACHE_TTL_SECONDS = Integer.parseInt(System.getenv().getOrDefault("REDIS_CACHE_TTL", "300"));

  private ArrayList<String> readFromCache() {
    try (Jedis jedis = new Jedis(REDIS_HOST, REDIS_PORT)) {
      List<String> cached = jedis.lrange(CACHE_KEY, 0, -1);
      if (cached != null && !cached.isEmpty()) {
        return new ArrayList<>(cached);
      }
    } catch (Exception e) {
      e.printStackTrace();
    }
    return null;
  }

  private void writeToCache(ArrayList<String> data) {
    if (data.isEmpty()) {
      return;
    }
    try (Jedis jedis = new Jedis(REDIS_HOST, REDIS_PORT)) {
      jedis.del(CACHE_KEY);
      jedis.rpush(CACHE_KEY, data.toArray(new String[0]));
      jedis.expire(CACHE_KEY, CACHE_TTL_SECONDS);
    } catch (Exception e) {
      e.printStackTrace();
    }
  }

  public ArrayList<String> getCustomerInformation() {
    ArrayList<String> cachedInfo = readFromCache();
    if (cachedInfo != null) {
      return cachedInfo;
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
}