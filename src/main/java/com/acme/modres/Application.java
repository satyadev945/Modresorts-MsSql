package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.context.annotation.Bean;

/**
 * Portable Spring Boot entry point (embedded Tomcat, fat JAR) replacing the
 * application-server (WebSphere/Liberty) provided runtime.
 */
@SpringBootApplication
@ServletComponentScan
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  // Filter mappings formerly declared in WEB-INF/web.xml
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
