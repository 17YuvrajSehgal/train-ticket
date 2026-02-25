package edu.fudan.common.tracing;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Auto-configuration for LTTng request tracing.
 *
 * Placed in edu.fudan.common.tracing — picked up automatically by
 * every service's @SpringBootApplication component scan of edu.fudan.**
 * No spring.factories needed. No changes to any individual service.
 *
 * Environment injection is the correct way to read spring.application.name
 * in Spring Boot — System.getProperty() does NOT work for this.
 */
@Configuration
public class LttngTracingAutoConfiguration implements WebMvcConfigurer {

    private final String serviceName;

    // Spring injects Environment which has the fully-resolved property
    // including application.yaml, bootstrap.yaml, env vars, etc.
    @Autowired
    public LttngTracingAutoConfiguration(Environment env) {
        // Fallback chain: spring.application.name → "unknown-service"
        this.serviceName = env.getProperty(
            "spring.application.name", "unknown-service");
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(new LttngRequestInterceptor(serviceName))
                .addPathPatterns("/**")
                // Exclude health checks and swagger — no value in tracing these
                .excludePathPatterns(
                    "/actuator/**",
                    "/swagger-ui.html",
                    "/v2/api-docs",
                    "/swagger-resources/**",
                    "/webjars/**"
                );
    }
}
