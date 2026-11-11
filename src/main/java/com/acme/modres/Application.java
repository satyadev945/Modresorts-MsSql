package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;
import org.springframework.context.annotation.Bean;

/**
 * Standalone Spring Boot entry point (embedded Tomcat) replacing the
 * application-server specific runtime.
 */
@SpringBootApplication
@ServletComponentScan
public class Application extends SpringBootServletInitializer {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  @Bean
  public FilterRegistrationBean<FirstFilter> firstFilter() {
    FilterRegistrationBean<FirstFilter> reg = new FilterRegistrationBean<>(new FirstFilter());
    reg.addUrlPatterns("/welcome");
    reg.setOrder(1);
    return reg;
  }

  @Bean
  public FilterRegistrationBean<SecondFilter> secondFilter() {
    FilterRegistrationBean<SecondFilter> reg = new FilterRegistrationBean<>(new SecondFilter());
    reg.addUrlPatterns("/welcome");
    reg.setOrder(2);
    return reg;
  }
}
