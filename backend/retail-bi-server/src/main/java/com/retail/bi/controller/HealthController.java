package com.retail.bi.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 应用健康检查控制器。
 *
 * 作用：
 * 1. 提供轻量级健康检查接口；
 * 2. 用于确认 Spring Boot 服务是否正常运行；
 * 3. 不依赖具体业务表，避免健康检查与业务查询耦合。
 */
@RestController
@RequestMapping("/api/v1")
public class HealthController {

    /**
     * 返回当前服务的基础运行状态。
     *
     * 请求地址：
     * GET /api/v1/health
     */
    @GetMapping("/health")
    public Map<String, Object> health() {

        // 使用 LinkedHashMap 保持返回字段的插入顺序，便于阅读。
        Map<String, Object> result = new LinkedHashMap<>();

        result.put("status", "UP");
        result.put("service", "retail-bi-server");
        result.put("timestamp", OffsetDateTime.now());

        return result;
    }
}