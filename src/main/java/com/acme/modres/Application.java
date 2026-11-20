package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.context.annotation.Bean;

/**
 * Standalone Spring Boot entry point using embedded Tomcat (no application-server dependency).
 */
@SpringBootApplication
@ServletComponentScan
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilter() {
    FilterRegistrationBean<FirstFilter> bean = new FilterRegistrationBean<>(new FirstFilter());
    bean.addUrlPatterns("/welcome");
    bean.setOrder(1);
    return bean;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilter() {
    FilterRegistrationBean<SecondFilter> bean = new FilterRegistrationBean<>(new SecondFilter());
    bean.addUrlPatterns("/welcome");
    bean.setOrder(2);
    return bean;
  }
}
