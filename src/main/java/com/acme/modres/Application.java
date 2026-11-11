package com.acme.modres;

import java.util.Collections;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.config.annotation.ViewControllerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Executable JAR entry point with embedded Tomcat. Replaces WAR deployment to an external
 * application server. Servlet/filter mappings formerly declared in WEB-INF/web.xml are
 * registered programmatically; @WebServlet annotated servlets are picked up by
 * {@link ServletComponentScan}.
 */
@SpringBootApplication
@ServletComponentScan
public class Application implements WebMvcConfigurer {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  @Bean
  public ServletRegistrationBean<WeatherServlet> weatherServletMapping() {
    ServletRegistrationBean<WeatherServlet> bean =
        new ServletRegistrationBean<>(new WeatherServlet(), "/weather");
    bean.setName("WeatherServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<AvailabilityCheckerServlet> availabilityServletMapping() {
    ServletRegistrationBean<AvailabilityCheckerServlet> bean =
        new ServletRegistrationBean<>(new AvailabilityCheckerServlet(), "/availability");
    bean.setName("AvailabilityCheckerServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<WelcomeServlet> welcomeServletMapping() {
    ServletRegistrationBean<WelcomeServlet> bean =
        new ServletRegistrationBean<>(new WelcomeServlet(), "/welcome");
    bean.setName("WelcomeServlet");
    return bean;
  }

  @Bean
  public ServletRegistrationBean<UpperServlet> upperServletMapping() {
    ServletRegistrationBean<UpperServlet> bean =
        new ServletRegistrationBean<>(new UpperServlet(), "/upper");
    bean.setName("UpperServlet");
    return bean;
  }

  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilterRegistration() {
    FilterRegistrationBean<FirstFilter> bean = new FilterRegistrationBean<>(new FirstFilter());
    bean.setUrlPatterns(Collections.singletonList("/welcome"));
    bean.setName("FirstFilter");
    bean.setOrder(1);
    return bean;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilterRegistration() {
    FilterRegistrationBean<SecondFilter> bean = new FilterRegistrationBean<>(new SecondFilter());
    bean.setUrlPatterns(Collections.singletonList("/welcome"));
    bean.setName("SecondFilter");
    bean.setOrder(2);
    return bean;
  }

  @Override
  public void addViewControllers(ViewControllerRegistry registry) {
    // login.jsp contains no dynamic JSP logic; served as static HTML from the executable JAR
    registry.addRedirectViewController("/login.jsp", "login.html");
  }
}
