package com.retail.bi.exception;

import com.retail.bi.common.ApiResponse;
import com.retail.bi.filter.RequestIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

/**
 * 全局异常处理器。
 *
 * 作用：
 * 1. 统一处理业务异常、参数异常和系统异常；
 * 2. 保证所有错误接口返回统一的 ApiResponse 格式；
 * 3. 防止数据库、SQL、代码堆栈等内部信息暴露给前端；
 * 4. 记录 requestId，便于通过前端响应定位后台日志。
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log =
            LoggerFactory.getLogger(GlobalExceptionHandler.class);

    /**
     * 处理业务异常。
     *
     * 例如：指定日期没有对应的销售概览数据。
     */
    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ApiResponse<Void>> handleBusinessException(
            BusinessException exception,
            HttpServletRequest request) {

        String requestId = getRequestId(request);

        log.warn(
                "业务异常，status={}, message={}",
                exception.getStatus(),
                exception.getMessage()
        );

        return ResponseEntity
                .status(exception.getStatus())
                .body(ApiResponse.error(
                        exception.getStatus().value(),
                        exception.getMessage(),
                        requestId
                ));
    }

    /**
     * 处理 URL 参数类型转换失败。
     *
     * 主要用于 @RequestParam、@PathVariable 等参数。
     */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ApiResponse<Void>> handleTypeMismatch(
            MethodArgumentTypeMismatchException exception,
            HttpServletRequest request) {

        String requestId = getRequestId(request);

        log.warn(
                "请求参数类型错误，parameter={}, value={}",
                exception.getName(),
                exception.getValue()
        );

        return ResponseEntity
                .badRequest()
                .body(ApiResponse.error(
                        400,
                        "请求参数格式错误",
                        requestId
                ));
    }

    /**
     * 处理 DTO 字段校验失败。
     *
     * 例如：请求体中没有传入必填的 date 字段。
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleValidationException(
            MethodArgumentNotValidException exception,
            HttpServletRequest request) {

        String requestId = getRequestId(request);

        // 当前返回第一个校验错误，避免一次返回过多无关信息。
        String message = exception
                .getBindingResult()
                .getAllErrors()
                .stream()
                .findFirst()
                .map(error -> error.getDefaultMessage())
                .orElse("请求参数校验失败");

        log.warn(
                "请求参数校验失败，message={}",
                message
        );

        return ResponseEntity
                .badRequest()
                .body(ApiResponse.error(
                        400,
                        message,
                        requestId
                ));
    }

    /**
     * 处理请求体读取或转换失败。
     *
     * 会进入这里的常见情况：
     * 1. 请求体完全缺失；
     * 2. 请求体不是合法 JSON；
     * 3. date=abc 无法转换为 LocalDate；
     * 4. JSON 字段类型与 DTO 字段类型不一致。
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> handleMessageNotReadable(
            HttpMessageNotReadableException exception,
            HttpServletRequest request) {

        String requestId = getRequestId(request);

        log.warn(
                "请求体读取失败，exceptionType={}, message={}",
                exception.getClass().getSimpleName(),
                exception.getMessage()
        );

        return ResponseEntity
                .badRequest()
                .body(ApiResponse.error(
                        400,
                        "请求体格式错误或缺失",
                        requestId
                ));
    }

    /**
     * 兜底处理未知系统异常。
     *
     * 前端只返回通用提示，后台保留完整异常堆栈。
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleException(
            Exception exception,
            HttpServletRequest request) {

        String requestId = getRequestId(request);

        log.error(
                "未处理的系统异常，exceptionType={}",
                exception.getClass().getName(),
                exception
        );

        return ResponseEntity
                .internalServerError()
                .body(ApiResponse.error(
                        500,
                        "服务器内部错误",
                        requestId
                ));
    }

    /**
     * 取得过滤器写入当前请求的 requestId。
     */
    private String getRequestId(HttpServletRequest request) {

        Object requestId = request.getAttribute(
                RequestIdFilter.REQUEST_ID
        );

        return requestId == null
                ? "unknown"
                : requestId.toString();
    }
}