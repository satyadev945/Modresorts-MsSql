package com.acme.modres;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.util.logging.Logger;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.List;
import javax.naming.InitialContext;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import com.acme.modres.mbean.IOUtils;
import com.acme.modres.mbean.reservation.DateChecker;
import com.acme.modres.mbean.reservation.ReservationCheckerData;
import com.acme.modres.mbean.reservation.Reservation;

import com.acme.modres.util.S3StorageUtil;

@WebServlet({ "/resorts/availability" })
public class AvailabilityCheckerServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  private static final Logger logger = Logger.getLogger(AvailabilityCheckerServlet.class.getName());

  private static InitialContext context;

  private ReservationCheckerData reservationCheckerData;

  @Override
  public void init() {
    // load reserved dates
    this.reservationCheckerData = new ReservationCheckerData(IOUtils.getReservationListFromConfig());
  }

  @Override
  protected void doGet(HttpServletRequest request, HttpServletResponse response) throws IOException, ServletException {

    String methodName = "doGet";
    logger.entering(AvailabilityCheckerServlet.class.getName(), methodName);
    int statusCode = 200;

    String selectedDateStr = request.getParameter("date");
    boolean parsedDate = reservationCheckerData.setSelectedDate(selectedDateStr);
    if (!parsedDate || reservationCheckerData.getReservationList() == null) {
      statusCode = 500;
      reservationCheckerData.setAvailablility(false);
    } else {
      List<Reservation> reservations = reservationCheckerData.getReservationList().getReservations();
      boolean isAvailible = true;

      for (Reservation reservation : reservations) {
        try {
          Instant fromDate = ReservationCheckerData.parseDate(reservation.getFromDate());
          Instant toDate = ReservationCheckerData.parseDate(reservation.getToDate());
          Instant selectedDate = reservationCheckerData.getSelectedDate();

          if (selectedDate.isAfter(fromDate) && selectedDate.isBefore(toDate)) {
            isAvailible = false;
            break;
          }
        } catch (DateTimeParseException ex) {
          ex.printStackTrace();
        }
      }

      reservationCheckerData.setAvailablility(isAvailible);

      // Adjust the status code based on availability
      if (!isAvailible) {
        statusCode = 201;
      }
    }

    // Send the response
    PrintWriter out = response.getWriter();
    response.setContentType("application/json");
    response.setCharacterEncoding("UTF-8");
    out.print("{\"availability\": \"" + String.valueOf(reservationCheckerData.isAvailible()) + "\"}");
    response.setStatus(statusCode);
  }

  /**
   * Returns the weather information for a given city
   */
  protected void doPost(HttpServletRequest request, HttpServletResponse response)
      throws ServletException, IOException {

    doGet(request, response);
  }

  protected int exportRevervations(String selectedDateStr) {
    final String sourceKey = "reservations.json";
    final String zipKey = "reservations.zip";

    try {
      // Read the reservations source from Amazon S3 (falls back to classpath when S3 is not configured)
      byte[] sourceBytes;
      if (S3StorageUtil.isConfigured()) {
        sourceBytes = S3StorageUtil.getObjectBytes(sourceKey);
      } else {
        try (InputStream is = AvailabilityCheckerServlet.class.getClassLoader().getResourceAsStream(sourceKey);
            ByteArrayOutputStream buffer = new ByteArrayOutputStream()) {
          if (is == null) {
            throw new FileNotFoundException(sourceKey);
          }
          byte[] chunk = new byte[1024];
          int read;
          while ((read = is.read(chunk)) >= 0) {
            buffer.write(chunk, 0, read);
          }
          sourceBytes = buffer.toByteArray();
        }
      }

      // Build the zip in memory (no local file system dependency)
      ByteArrayOutputStream zipBytes = new ByteArrayOutputStream();
      try (ZipOutputStream zipOut = new ZipOutputStream(zipBytes)) {
        zipOut.putNextEntry(new ZipEntry(sourceKey));
        zipOut.write(sourceBytes, 0, sourceBytes.length);
        zipOut.closeEntry();
      }
      byte[] zipData = zipBytes.toByteArray();

      // verify zip
      boolean valid;
      try (ZipInputStream zis = new ZipInputStream(new ByteArrayInputStream(zipData))) {
        valid = zis.getNextEntry() != null;
      }

      if (valid) {
        if (S3StorageUtil.isConfigured()) {
          S3StorageUtil.putObject(zipKey, zipData, "application/zip");
        } else {
          logger.warning("S3_BUCKET_NAME is not set; exported zip was validated but not persisted");
        }
        return 0;
      }
    } catch (FileNotFoundException e) {
      e.printStackTrace();
    } catch (IOException e) {
      e.printStackTrace();
    } catch (Throwable e) {
      e.printStackTrace();
    }
    return -1;
  }

}
