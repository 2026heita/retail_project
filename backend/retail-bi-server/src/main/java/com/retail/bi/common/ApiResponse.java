package com.retail.bi.common;

public record ApiResponse<T>(
        int code,
        String message,
        T data,
        String requestId
) {

    public static <T> ApiResponse<T> success(
            T data,
            String requestId) {

        return new ApiResponse<>(
                200,
                "success",
                data,
                requestId
        );
    }

    public static <T> ApiResponse<T> error(
            int code,
            String message,
            String requestId) {

        return new ApiResponse<>(
                code,
                message,
                null,
                requestId
        );
    }
}