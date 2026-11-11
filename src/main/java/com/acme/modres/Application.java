package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;
import org.springframework.context.annotation.Bean;

/**
 * Spring Boot entry point: runs the application as an executable JAR with embedded Tomcat.
 * Servlet/filter mappings previously declared in WEB-INF/web.xml are registered programmatically.
 */
@SpringBootApplication
@ServletComponentScan(basePackages = "com.acme.modres")
public class Application extends SpringBootServletInitializer {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  @Bean
  public ServletRegistrationBean<WeatherServlet> weatherServletRegistration() {
    return new ServletRegistrationBean<>(new WeatherServlet(), "/weather");
  }

  @Bean
  public ServletRegistrationBean<AvailabilityCheckerServlet> availabilityServletRegistration() {
    return new ServletRegistrationBean<>(new AvailabilityCheckerServlet(), "/availability");
  }

  @Bean
  public ServletRegistrationBean<WelcomeServlet> welcomeServletRegistration() {
    return new ServletRegistrationBean<>(new WelcomeServlet(), "/welcome");
  }

  @Bean
  public ServletRegistrationBean<UpperServlet> upperServletRegistration() {
    return new ServletRegistrationBean<>(new UpperServlet(), "/upper");
  }

  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilterRegistration() {
    FilterRegistrationBean<FirstFilter> reg = new FilterRegistrationBean<>(new FirstFilter());
    reg.addUrlPatterns("/welcome");
    reg.setOrder(1);
    return reg;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilterRegistration() {
    FilterRegistrationBean<SecondFilter> reg = new FilterRegistrationBean<>(new SecondFilter());
    reg.addUrlPatterns("/welcome");
    reg.setOrder(2);
    return reg;
  }
}
