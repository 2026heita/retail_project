package com.retail.bi.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web 跨域访问配置。
 *
 * 作用：
 * 1. 允许本地前端开发服务器调用零售 BI 接口；
 * 2. 允许浏览器读取后端返回的 X-Request-Id；
 * 3. 统一管理跨域规则，避免在各 Controller 重复配置。
 */
@Configuration
public class WebCorsConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns(
                        "http://localhost:*",
                        "http://127.0.0.1:*"
                )
                .allowedMethods("GET", "OPTIONS")
                .allowedHeaders("*")
                .exposedHeaders("X-Request-Id")
                .allowCredentials(false)
                .maxAge(3600);
    }
}