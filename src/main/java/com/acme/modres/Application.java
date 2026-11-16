package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;

/**
 * Executable entry point with embedded Tomcat (replaces WAR deployment and web.xml).
 */
@SpringBootApplication
@ServletComponentScan(basePackages = "com.acme.modres")
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  // Equivalent of the servlet/filter mappings previously declared in WEB-INF/web.xml
  @Bean
  public ServletRegistrationBean<WeatherServlet> weatherServletLegacy() {
    ServletRegistrationBean<WeatherServlet> b = new ServletRegistrationBean<>(new WeatherServlet(), "/weather");
    b.setName("WeatherServlet");
    return b;
  }

  @Bean
  public ServletRegistrationBean<AvailabilityCheckerServlet> availabilityServletLegacy() {
    ServletRegistrationBean<AvailabilityCheckerServlet> b =
        new ServletRegistrationBean<>(new AvailabilityCheckerServlet(), "/availability");
    b.setName("AvailabilityCheckerServlet");
    return b;
  }

  @Bean
  public ServletRegistrationBean<WelcomeServlet> welcomeServletLegacy() {
    ServletRegistrationBean<WelcomeServlet> b = new ServletRegistrationBean<>(new WelcomeServlet(), "/welcome");
    b.setName("WelcomeServlet");
    return b;
  }

  @Bean
  public ServletRegistrationBean<UpperServlet> upperServletLegacy() {
    ServletRegistrationBean<UpperServlet> b = new ServletRegistrationBean<>(new UpperServlet(), "/upper");
    b.setName("UpperServlet");
    return b;
  }

  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilter() {
    FilterRegistrationBean<FirstFilter> b = new FilterRegistrationBean<>(new FirstFilter());
    b.addUrlPatterns("/welcome");
    b.setOrder(1);
    return b;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilter() {
    FilterRegistrationBean<SecondFilter> b = new FilterRegistrationBean<>(new SecondFilter());
    b.addUrlPatterns("/welcome");
    b.setOrder(2);
    return b;
  }
}
