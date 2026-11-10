package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;

/**
 * Executable entry point with embedded Tomcat (replaces WAR deployment to an
 * external application server). Servlet/filter mappings previously declared in
 * WEB-INF/web.xml are registered programmatically because web.xml is not
 * processed by the embedded container. The listening port is taken from the
 * PORT / SERVER_PORT environment variable (default 8080).
 */
@SpringBootApplication
@ServletComponentScan(basePackages = "com.acme.modres")
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  @Bean
  public ServletRegistrationBean<WeatherServlet> weatherServletRegistration() {
    ServletRegistrationBean<WeatherServlet> bean = new ServletRegistrationBean<>(new WeatherServlet(), "/weather");
    bean.setName("WeatherServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<AvailabilityCheckerServlet> availabilityServletRegistration() {
    ServletRegistrationBean<AvailabilityCheckerServlet> bean = new ServletRegistrationBean<>(
        new AvailabilityCheckerServlet(), "/availability");
    bean.setName("AvailabilityCheckerServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<WelcomeServlet> welcomeServletRegistration() {
    ServletRegistrationBean<WelcomeServlet> bean = new ServletRegistrationBean<>(new WelcomeServlet(), "/welcome");
    bean.setName("WelcomeServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<UpperServlet> upperServletRegistration() {
    ServletRegistrationBean<UpperServlet> bean = new ServletRegistrationBean<>(new UpperServlet(), "/upper");
    bean.setName("UpperServlet");
    return bean;
  }

  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilterRegistration() {
    FilterRegistrationBean<FirstFilter> bean = new FilterRegistrationBean<>(new FirstFilter());
    bean.addUrlPatterns("/welcome");
    bean.setName("FirstFilter");
    bean.setOrder(1);
    return bean;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilterRegistration() {
    FilterRegistrationBean<SecondFilter> bean = new FilterRegistrationBean<>(new SecondFilter());
    bean.addUrlPatterns("/welcome");
    bean.setName("SecondFilter");
    bean.setOrder(2);
    return bean;
  }
}
