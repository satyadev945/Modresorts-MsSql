package com.acme.modres;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;

import javax.servlet.Filter;
import javax.servlet.FilterChain;
import javax.servlet.FilterConfig;
import javax.servlet.ServletException;
import javax.servlet.ServletOutputStream;
import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import javax.servlet.WriteListener;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpServletResponseWrapper;

/**
 * Generates a per-request cryptographically random CSP nonce, injects it into HTML
 * responses (replacing the {{CSP_NONCE}} placeholder) and emits a matching
 * Content-Security-Policy header. Intended to run behind Cloud Run / Cloud Armor,
 * which enforce the policy at the edge and rely on the app for nonce rendering.
 *
 * The policy can be overridden through the CSP_POLICY_TEMPLATE environment variable;
 * "{nonce}" in the template is replaced with the generated nonce.
 */
public class CspNonceFilter implements Filter {

  private static final String PLACEHOLDER = "{{CSP_NONCE}}";
  private static final String NONCE_ATTRIBUTE = "cspNonce";
  private static final String DEFAULT_POLICY = "default-src 'self'; "
      + "script-src 'self' 'nonce-{nonce}'; "
      + "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
      + "font-src 'self' https://fonts.gstatic.com; "
      + "img-src 'self' data: https://icons.wxug.com; "
      + "connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'";

  private final SecureRandom random = new SecureRandom();
  private String policyTemplate = DEFAULT_POLICY;

  @Override
  public void init(FilterConfig filterConfig) throws ServletException {
    String env = System.getenv("CSP_POLICY_TEMPLATE");
    if (env != null && !env.trim().isEmpty()) {
      policyTemplate = env;
    }
  }

  @Override
  public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
      throws IOException, ServletException {
    if (!(response instanceof HttpServletResponse)) {
      chain.doFilter(request, response);
      return;
    }
    HttpServletResponse res = (HttpServletResponse) response;

    byte[] bytes = new byte[16];
    random.nextBytes(bytes);
    String nonce = Base64.getEncoder().encodeToString(bytes);

    request.setAttribute(NONCE_ATTRIBUTE, nonce);
    res.setHeader("Content-Security-Policy", policyTemplate.replace("{nonce}", nonce));

    BufferingResponse wrapper = new BufferingResponse(res);
    chain.doFilter(request, wrapper);
    wrapper.flushBuffer();

    byte[] body = wrapper.getBytes();
    String contentType = wrapper.getContentType();
    if (contentType != null && contentType.toLowerCase().startsWith("text/html")) {
      Charset cs = wrapper.getCharacterEncoding() != null
          ? Charset.forName(wrapper.getCharacterEncoding()) : StandardCharsets.UTF_8;
      body = new String(body, cs).replace(PLACEHOLDER, nonce).getBytes(cs);
    }
    res.setContentLength(body.length);
    res.getOutputStream().write(body);
    res.getOutputStream().flush();
  }

  @Override
  public void destroy() {
    // nothing to release
  }

  private static class BufferingResponse extends HttpServletResponseWrapper {
    private final ByteArrayOutputStream buffer = new ByteArrayOutputStream();
    private ServletOutputStream stream;
    private PrintWriter writer;

    BufferingResponse(HttpServletResponse response) {
      super(response);
    }

    byte[] getBytes() {
      return buffer.toByteArray();
    }

    @Override
    public ServletOutputStream getOutputStream() throws IOException {
      if (stream == null) {
        stream = new ServletOutputStream() {
          @Override
          public void write(int b) {
            buffer.write(b);
          }

          @Override
          public boolean isReady() {
            return true;
          }

          @Override
          public void setWriteListener(WriteListener listener) {
            // synchronous buffering only
          }
        };
      }
      return stream;
    }

    @Override
    public PrintWriter getWriter() throws IOException {
      if (writer == null) {
        String enc = getCharacterEncoding() != null ? getCharacterEncoding() : "UTF-8";
        writer = new PrintWriter(new OutputStreamWriter(getOutputStream(), enc));
      }
      return writer;
    }

    @Override
    public void setContentLength(int len) {
      // length is recalculated after nonce injection
    }

    @Override
    public void setContentLengthLong(long len) {
      // length is recalculated after nonce injection
    }

    @Override
    public void flushBuffer() throws IOException {
      if (writer != null) {
        writer.flush();
      }
    }
  }
}
