package com.acme.modres;

import java.io.File;
import java.net.URL;
import java.security.CodeSource;

import org.apache.catalina.Context;
import org.apache.catalina.WebResourceRoot;
import org.apache.catalina.startup.Tomcat;
import org.apache.catalina.webresources.DirResourceSet;
import org.apache.catalina.webresources.JarResourceSet;
import org.apache.catalina.webresources.StandardRoot;

/**
 * Entry point for running ModResorts as an executable JAR with embedded Tomcat
 * (replaces deployment of a WAR to an external application server).
 *
 * The listening port is read from the PORT (or SERVER_PORT) environment variable
 * and defaults to 8080.
 */
public class Application {

  private static String env(String name, String def) {
    String v = System.getenv(name);
    return (v == null || v.trim().isEmpty()) ? def : v.trim();
  }

  public static void main(String[] args) throws Exception {
    int port = Integer.parseInt(env("PORT", env("SERVER_PORT", "8080")));

    Tomcat tomcat = new Tomcat();
    tomcat.setBaseDir(env("TOMCAT_BASE_DIR", System.getProperty("java.io.tmpdir") + "/modresorts-tomcat"));
    tomcat.setPort(port);
    tomcat.getConnector();

    File docBase = new File(System.getProperty("java.io.tmpdir"), "modresorts-docbase");
    docBase.mkdirs();
    Context ctx = tomcat.addContext("", docBase.getAbsolutePath());
    Tomcat.initWebappDefaults(ctx);
    ctx.setSessionTimeout(30);

    // Static content / JSPs are packaged under /webapp inside the JAR
    WebResourceRoot resources = new StandardRoot(ctx);
    CodeSource cs = Application.class.getProtectionDomain().getCodeSource();
    URL location = cs == null ? null : cs.getLocation();
    if (location != null && location.getPath().endsWith(".jar")) {
      resources.addPreResources(new JarResourceSet(resources, "/", new File(location.toURI()).getAbsolutePath(), "/webapp"));
    } else {
      File webContent = new File(env("WEB_CONTENT_DIR", "WebContent"));
      resources.addPreResources(new DirResourceSet(resources, "/", webContent.getAbsolutePath(), "/"));
    }
    ctx.setResources(resources);

    // Servlets (equivalent to WEB-INF/web.xml and @WebServlet mappings)
    addServlet(ctx, "WeatherServlet", new WeatherServlet(), "/weather", "/resorts/weather");
    addServlet(ctx, "AvailabilityCheckerServlet", new AvailabilityCheckerServlet(), "/availability",
        "/resorts/availability");
    addServlet(ctx, "WelcomeServlet", new WelcomeServlet(), "/welcome", "/resorts/welcome");
    addServlet(ctx, "UpperServlet", new UpperServlet(), "/upper", "/resorts/upper");
    addServlet(ctx, "LogoutServlet", new LogoutServlet(), "/logout");

    // Filters
    addFilter(ctx, "FirstFilter", new FirstFilter(), "/welcome");
    addFilter(ctx, "SecondFilter", new SecondFilter(), "/welcome");

    ctx.addWelcomeFile("index.html");

    tomcat.start();
    tomcat.getServer().await();
  }

  private static void addServlet(Context ctx, String name, javax.servlet.Servlet servlet, String... patterns) {
    Tomcat.addServlet(ctx, name, servlet);
    for (String p : patterns) {
      ctx.addServletMappingDecoded(p, name);
    }
  }

  private static void addFilter(Context ctx, String name, javax.servlet.Filter filter, String... patterns) {
    org.apache.tomcat.util.descriptor.web.FilterDef def = new org.apache.tomcat.util.descriptor.web.FilterDef();
    def.setFilterName(name);
    def.setFilter(filter);
    ctx.addFilterDef(def);
    org.apache.tomcat.util.descriptor.web.FilterMap map = new org.apache.tomcat.util.descriptor.web.FilterMap();
    map.setFilterName(name);
    for (String p : patterns) {
      map.addURLPattern(p);
    }
    ctx.addFilterMap(map);
  }
}
