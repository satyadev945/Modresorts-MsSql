package com.acme.modres;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.util.logging.Logger;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
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

import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@WebServlet({ "/resorts/availability" })
public class AvailabilityCheckerServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  private static final Logger logger = Logger.getLogger(AvailabilityCheckerServlet.class.getName());

  private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern(Constants.DATA_FORMAT);

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
          Instant fromDate = LocalDate.parse(reservation.getFromDate(), DATE_FORMATTER).atStartOfDay(ZoneOffset.UTC).toInstant();
          Instant toDate = LocalDate.parse(reservation.getToDate(), DATE_FORMATTER).atStartOfDay(ZoneOffset.UTC).toInstant();
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
    response.setContentType("application/json");
    response.setCharacterEncoding("UTF-8");
    response.setStatus(statusCode);
    try (PrintWriter out = response.getWriter()) {
      out.print("{\"availability\": \"" + String.valueOf(reservationCheckerData.isAvailible()) + "\"}");
    }
  }

  /**
   * Returns the weather information for a given city
   */
  protected void doPost(HttpServletRequest request, HttpServletResponse response)
      throws ServletException, IOException {

    doGet(request, response);
  }

  protected int exportRevervations(String selectedDateStr) {
    // Reservations export is stored in Amazon S3 instead of the local file system.
    String bucket = System.getenv("RESERVATIONS_EXPORT_S3_BUCKET");
    String key = System.getenv().getOrDefault("RESERVATIONS_EXPORT_S3_KEY", "exports/reservations.zip");
    if (bucket == null || bucket.isEmpty()) {
      logger.severe("RESERVATIONS_EXPORT_S3_BUCKET environment variable is not set");
      return -1;
    }

    try (InputStream fis = AvailabilityCheckerServlet.class.getClassLoader()
        .getResourceAsStream("reservations.json")) {
      if (fis == null) {
        logger.severe("reservations.json not found on classpath");
        return -1;
      }

      // build the zip in memory
      ByteArrayOutputStream bos = new ByteArrayOutputStream();
      try (ZipOutputStream zipOut = new ZipOutputStream(bos)) {
        zipOut.putNextEntry(new ZipEntry("reservations.json"));
        byte[] bytes = new byte[1024];
        int length;
        while ((length = fis.read(bytes)) >= 0) {
          zipOut.write(bytes, 0, length);
        }
        zipOut.closeEntry();
      }
      byte[] zipBytes = bos.toByteArray();

      // verify zip
      try (ZipInputStream zis = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
        if (zis.getNextEntry() == null) {
          return -1;
        }
      }

      // upload to S3
      try (S3Client s3 = S3Client.create()) {
        s3.putObject(PutObjectRequest.builder().bucket(bucket).key(key).contentType("application/zip").build(),
            RequestBody.fromBytes(zipBytes));
      }
      return 0;
    } catch (Throwable e) {
      e.printStackTrace();
    }
    return -1;
  }

}