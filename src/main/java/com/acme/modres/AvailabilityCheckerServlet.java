package com.acme.modres;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.logging.Logger;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import java.time.LocalDate;
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
          LocalDate fromDate = LocalDate.parse(reservation.getFromDate(), DATE_FORMATTER);
          LocalDate toDate = LocalDate.parse(reservation.getToDate(), DATE_FORMATTER);
          LocalDate selectedDate = reservationCheckerData.getSelectedDate();

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
    try {
      byte[] json = IOUtils.getBytesFromRelativePath("reservations.json");
      if (json == null) {
        logger.severe("reservations.json resource not found");
        return -1;
      }

      // Build the zip entirely in memory (no local file system writes)
      ByteArrayOutputStream bos = new ByteArrayOutputStream();
      try (ZipOutputStream zipOut = new ZipOutputStream(bos)) {
        zipOut.putNextEntry(new ZipEntry("reservations.json"));
        zipOut.write(json, 0, json.length);
        zipOut.closeEntry();
      }
      byte[] zipBytes = bos.toByteArray();

      // verify zip (in memory)
      boolean valid;
      try (ZipInputStream zin = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
        valid = zin.getNextEntry() != null;
      }
      if (valid) {
        // Persist the export to Amazon S3 instead of the local file system
        String bucket = System.getenv("RESERVATIONS_S3_BUCKET");
        String key = System.getenv().getOrDefault("RESERVATIONS_S3_KEY", "reservations.zip");
        if (bucket == null || bucket.isEmpty()) {
          logger.severe("RESERVATIONS_S3_BUCKET environment variable is not set");
          return -1;
        }
        try (S3Client s3 = S3Client.create()) {
          s3.putObject(PutObjectRequest.builder().bucket(bucket).key(key).build(),
              RequestBody.fromBytes(zipBytes));
        }
        return 0;
      }
    } catch (Throwable e) {
      e.printStackTrace();
    }
    return -1;
  }

}
