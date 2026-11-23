package com.acme.modres;

import com.acme.modres.db.ModResortsCustomerInformation;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;

/**
 * Executable entry point. Runs the application with an embedded Tomcat
 * (Spring Boot) instead of deploying a WAR to an external application server.
 * The port is configurable through the PORT / SERVER_PORT environment variable.
 */
@SpringBootApplication
@ServletComponentScan(basePackages = "com.acme.modres")
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  // Makes the former CDI bean injectable (@Inject) into the servlets.
  @Bean
  public ModResortsCustomerInformation modResortsCustomerInformation() {
    return new ModResortsCustomerInformation();
  }

  // Programmatic equivalents of the web.xml servlet/filter declarations,
  // since embedded Tomcat does not process WEB-INF/web.xml.
  @Bean
  public ServletRegistrationBean<WeatherServlet> weatherServlet() {
    ServletRegistrationBean<WeatherServlet> bean = new ServletRegistrationBean<>(new WeatherServlet(), "/weather");
    bean.setName("WeatherServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<AvailabilityCheckerServlet> availabilityCheckerServlet() {
    ServletRegistrationBean<AvailabilityCheckerServlet> bean =
        new ServletRegistrationBean<>(new AvailabilityCheckerServlet(), "/availability");
    bean.setName("AvailabilityCheckerServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<WelcomeServlet> welcomeServlet() {
    ServletRegistrationBean<WelcomeServlet> bean = new ServletRegistrationBean<>(new WelcomeServlet(), "/welcome");
    bean.setName("WelcomeServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<UpperServlet> upperServlet() {
    ServletRegistrationBean<UpperServlet> bean = new ServletRegistrationBean<>(new UpperServlet(), "/upper");
    bean.setName("UpperServlet");
    return bean;
  }

  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilter() {
    FilterRegistrationBean<FirstFilter> bean = new FilterRegistrationBean<>();
    bean.setFilter(new FirstFilter());
    bean.addUrlPatterns("/welcome");
    bean.setName("FirstFilter");
    bean.setOrder(1);
    return bean;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilter() {
    FilterRegistrationBean<SecondFilter> bean = new FilterRegistrationBean<>();
    bean.setFilter(new SecondFilter());
    bean.addUrlPatterns("/welcome");
    bean.setName("SecondFilter");
    bean.setOrder(2);
    return bean;
  }
}
