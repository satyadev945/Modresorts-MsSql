package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;

/**
 * Executable JAR entry point with embedded Tomcat (replaces WAR deployment and
 * the servlet/filter declarations previously held in WEB-INF/web.xml).
 */
@SpringBootApplication
@ServletComponentScan(basePackages = "com.acme.modres")
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    @Bean
    public ServletRegistrationBean<WeatherServlet> weatherServletLegacy() {
        ServletRegistrationBean<WeatherServlet> bean = new ServletRegistrationBean<>(new WeatherServlet(), "/weather");
        bean.setName("WeatherServlet");
        return bean;
    }

    @Bean
    public ServletRegistrationBean<AvailabilityCheckerServlet> availabilityServletLegacy() {
        ServletRegistrationBean<AvailabilityCheckerServlet> bean = new ServletRegistrationBean<>(
                new AvailabilityCheckerServlet(), "/availability");
        bean.setName("AvailabilityCheckerServlet");
        return bean;
    }

    @Bean
    public ServletRegistrationBean<WelcomeServlet> welcomeServletLegacy() {
        ServletRegistrationBean<WelcomeServlet> bean = new ServletRegistrationBean<>(new WelcomeServlet(), "/welcome");
        bean.setName("WelcomeServlet");
        return bean;
    }

    @Bean
    public ServletRegistrationBean<UpperServlet> upperServletLegacy() {
        ServletRegistrationBean<UpperServlet> bean = new ServletRegistrationBean<>(new UpperServlet(), "/upper");
        bean.setName("UpperServlet");
        return bean;
    }

    @Bean
    public FilterRegistrationBean<FirstFilter> firstFilter() {
        FilterRegistrationBean<FirstFilter> bean = new FilterRegistrationBean<>(new FirstFilter());
        bean.addUrlPatterns("/welcome");
        bean.setName("FirstFilter");
        bean.setOrder(1);
        return bean;
    }

    @Bean
    public FilterRegistrationBean<SecondFilter> secondFilter() {
        FilterRegistrationBean<SecondFilter> bean = new FilterRegistrationBean<>(new SecondFilter());
        bean.addUrlPatterns("/welcome");
        bean.setName("SecondFilter");
        bean.setOrder(2);
        return bean;
    }

    @Bean
    public FilterRegistrationBean<CspNonceFilter> cspNonceFilter() {
        FilterRegistrationBean<CspNonceFilter> bean = new FilterRegistrationBean<>(new CspNonceFilter());
        bean.addUrlPatterns("/index.html", "/");
        bean.setName("CspNonceFilter");
        bean.setOrder(3);
        return bean;
    }
}
