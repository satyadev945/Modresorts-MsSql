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
      // Standard Servlet API logout (replaces WSSecurityHelper.revokeSSOCookies)
      request.logout();
      javax.servlet.http.HttpSession session = request.getSession(false);
      if (session != null) {
        session.invalidate();
      }
      javax.servlet.http.Cookie ltpa = new javax.servlet.http.Cookie("LtpaToken2", "");
      ltpa.setMaxAge(0);
      ltpa.setPath("/");
      response.addCookie(ltpa);
    } catch (Exception e) {
      System.err.println("[ERROR] Error logging out");
      e.printStackTrace();
    }

    response.sendRedirect("login.jsp");
  }
}
