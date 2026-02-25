package edu.fudan.common.tracing;

import org.lttng.ust.agent.jul.LttngLogHandler;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.logging.Logger;

/**
 * Spring MVC interceptor that emits LTTng-UST tracepoints at the
 * boundary of every HTTP request — exact analog of Apache's
 * httpd:enter_event_handler / httpd:exit_event_handler.
 *
 * Registered once in ts-common; auto-applied to all services.
 * serviceName is injected from Spring Environment so it correctly
 * reads spring.application.name (e.g. "ts-order-service").
 */
public class LttngRequestInterceptor implements HandlerInterceptor {

    // Single shared logger — name must match lttng enable-event --jul
    private static final Logger LTTNG =
        Logger.getLogger("trainticket.request");

    // ThreadLocal: safe for concurrent Tomcat threads, no contention
    private static final ThreadLocal<Long> START_NS = new ThreadLocal<>();

    // Injected by LttngTracingAutoConfiguration via constructor
    private final String serviceName;

    public LttngRequestInterceptor(String serviceName) {
        this.serviceName = serviceName;
        try {
            LTTNG.addHandler(new LttngLogHandler());
        } catch (Exception e) {
            // LTTng agent not loaded (unit tests / non-Linux) — degrade silently
        }
    }

    @Override
    public boolean preHandle(HttpServletRequest request,
                             HttpServletResponse response,
                             Object handler) {
        START_NS.set(System.nanoTime());

        // ENTER:<service>:<HTTP_method>:<uri>:<tid>
        // tid is the primary key — trace_reader joins on this to
        // match kernel syscall events to the correct request sequence
        String msg = String.format("ENTER:%s:%s:%s:%d",
            serviceName,
            request.getMethod(),
            request.getRequestURI(),
            Thread.currentThread().getId());

        LTTNG.info(msg);
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request,
                                HttpServletResponse response,
                                Object handler,
                                Exception ex) {
        long durationNs = System.nanoTime() - START_NS.get();
        START_NS.remove();  // prevent memory leak in thread pools

        // EXIT:<service>:<http_status>:<duration_ns>:<tid>
        // duration_ns here is total wall-clock request time —
        // useful for sanity-checking against req_dur in the NPZ shard
        String msg = String.format("EXIT:%s:%d:%d:%d",
            serviceName,
            response.getStatus(),
            durationNs,
            Thread.currentThread().getId());

        LTTNG.info(msg);
    }
}
