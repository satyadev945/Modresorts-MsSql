package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;

/**
 * Spring Boot entry point. Replaces WAR deployment (web.xml / external application
 * server) with an executable JAR running embedded Tomcat.
 */
@SpringBootApplication
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  // Servlets (previously declared via @WebServlet and web.xml)
  @Bean
  public WeatherServlet weatherServlet() {
    return new WeatherServlet();
  }

  @Bean
  public ServletRegistrationBean<WeatherServlet> weatherServletRegistration(WeatherServlet servlet) {
    return new ServletRegistrationBean<>(servlet, "/resorts/weather", "/weather");
  }

  @Bean
  public AvailabilityCheckerServlet availabilityCheckerServlet() {
    return new AvailabilityCheckerServlet();
  }

  @Bean
  public ServletRegistrationBean<AvailabilityCheckerServlet> availabilityServletRegistration(
      AvailabilityCheckerServlet servlet) {
    return new ServletRegistrationBean<>(servlet, "/resorts/availability", "/availability");
  }

  @Bean
  public WelcomeServlet welcomeServlet() {
    return new WelcomeServlet();
  }

  @Bean
  public ServletRegistrationBean<WelcomeServlet> welcomeServletRegistration(WelcomeServlet servlet) {
    return new ServletRegistrationBean<>(servlet, "/resorts/welcome", "/welcome");
  }

  @Bean
  public UpperServlet upperServlet() {
    return new UpperServlet();
  }

  @Bean
  public ServletRegistrationBean<UpperServlet> upperServletRegistration(UpperServlet servlet) {
    return new ServletRegistrationBean<>(servlet, "/resorts/upper", "/upper");
  }

  @Bean
  public LogoutServlet logoutServlet() {
    return new LogoutServlet();
  }

  @Bean
  public ServletRegistrationBean<LogoutServlet> logoutServletRegistration(LogoutServlet servlet) {
    return new ServletRegistrationBean<>(servlet, "/logout");
  }

  // Filters (previously declared in web.xml)
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
