package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.context.annotation.Bean;

/**
 * Portable Spring Boot entry point (embedded Tomcat, fat JAR) replacing the
 * application-server (WebSphere/Liberty) deployment.
 */
@SpringBootApplication
@ServletComponentScan
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }

  // Equivalent of the filter mappings previously declared in WEB-INF/web.xml
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
