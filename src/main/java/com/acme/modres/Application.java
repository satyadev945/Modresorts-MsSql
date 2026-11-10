package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.context.annotation.Bean;

/**
 * Executable entry point. Runs the application on an embedded Tomcat server
 * (packaged as a self-contained JAR) instead of deploying a WAR to an external
 * application server. The listen port is taken from the PORT / SERVER_PORT
 * environment variable (see application.properties).
 */
@SpringBootApplication
@ServletComponentScan(basePackages = "com.acme.modres")
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  // Equivalent of the <filter>/<filter-mapping> entries previously declared in web.xml
  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilterRegistration() {
    FilterRegistrationBean<FirstFilter> registration = new FilterRegistrationBean<>(new FirstFilter());
    registration.addUrlPatterns("/welcome");
    registration.setOrder(1);
    return registration;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilterRegistration() {
    FilterRegistrationBean<SecondFilter> registration = new FilterRegistrationBean<>(new SecondFilter());
    registration.addUrlPatterns("/welcome");
    registration.setOrder(2);
    return registration;
  }
}
