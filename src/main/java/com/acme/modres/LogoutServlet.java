package com.acme.modres;

import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import java.io.IOException;

@WebServlet({ "/logout" })
public class LogoutServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request,
      HttpServletResponse response) throws IOException {

    try {
      // Container-neutral logout (replaces WebSphere WSSecurityHelper.revokeSSOCookies)
      request.logout();
      javax.servlet.http.HttpSession session = request.getSession(false);
      if (session != null) {
        session.invalidate();
      }
      javax.servlet.http.Cookie[] cookies = request.getCookies();
      if (cookies != null) {
        for (javax.servlet.http.Cookie cookie : cookies) {
          if ("LtpaToken2".equals(cookie.getName()) || "LtpaToken".equals(cookie.getName())
              || "JSESSIONID".equals(cookie.getName())) {
            javax.servlet.http.Cookie expired = new javax.servlet.http.Cookie(cookie.getName(), "");
            expired.setMaxAge(0);
            expired.setPath("/");
            response.addCookie(expired);
          }
        }
      }
    } catch (Exception e) {
      System.err.println("[ERROR] Error logging out");
      e.printStackTrace();
    }

    response.sendRedirect("login.jsp");
  }
}
