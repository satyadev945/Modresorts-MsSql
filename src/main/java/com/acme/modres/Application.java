package com.acme.modres;

import java.util.Collections;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;

/**
 * Spring Boot entry point. Runs the application as an executable JAR with an
 * embedded Tomcat server (replaces WAR deployment to an external app server).
 * The servlet/filter mappings previously declared in WEB-INF/web.xml are
 * registered programmatically below; @WebServlet annotated servlets are
 * discovered via @ServletComponentScan.
 */
@SpringBootApplication
@ServletComponentScan
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  @Bean
  public ServletRegistrationBean<WeatherServlet> weatherServletLegacy() {
    return new ServletRegistrationBean<>(new WeatherServlet(), "/weather");
  }

  @Bean
  public ServletRegistrationBean<AvailabilityCheckerServlet> availabilityServletLegacy() {
    return new ServletRegistrationBean<>(new AvailabilityCheckerServlet(), "/availability");
  }

  @Bean
  public ServletRegistrationBean<WelcomeServlet> welcomeServletLegacy() {
    return new ServletRegistrationBean<>(new WelcomeServlet(), "/welcome");
  }

  @Bean
  public ServletRegistrationBean<UpperServlet> upperServletLegacy() {
    return new ServletRegistrationBean<>(new UpperServlet(), "/upper");
  }

  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilterRegistration() {
    FilterRegistrationBean<FirstFilter> reg = new FilterRegistrationBean<>(new FirstFilter());
    reg.setUrlPatterns(Collections.singletonList("/welcome"));
    reg.setOrder(1);
    return reg;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilterRegistration() {
    FilterRegistrationBean<SecondFilter> reg = new FilterRegistrationBean<>(new SecondFilter());
    reg.setUrlPatterns(Collections.singletonList("/welcome"));
    reg.setOrder(2);
    return reg;
  }
}
