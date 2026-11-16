package com.acme.modres;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.logging.Logger;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import java.text.ParseException;
import java.util.Date;
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

import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;

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
          Date fromDate = Constants.utcDateFormat().parse(reservation.getFromDate());
          Date toDate = Constants.utcDateFormat().parse(reservation.getToDate());
          Date selectedDate = reservationCheckerData.getSelectedDate();

          if (selectedDate.after(fromDate) && selectedDate.before(toDate)) {
            isAvailible = false;
            break;
          }
        } catch (ParseException ex) {
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
    byte[] reservationBytes = IOUtils.getBytesFromRelativePath("reservations.json");
    if (reservationBytes == null) {
      logger.severe("reservations.json resource not found; cannot export reservations");
      return -1;
    }

    // Cloud-native: build the archive in memory and store it in Google Cloud Storage
    // instead of writing to a host-specific path (user.home).
    String bucketName = System.getenv("GCS_BUCKET_NAME");
    String objectName = System.getenv().getOrDefault("GCS_RESERVATIONS_ZIP_OBJECT", "reservations.zip");
    if (bucketName == null || bucketName.isEmpty()) {
      logger.severe("GCS_BUCKET_NAME environment variable is not set; cannot export reservations");
      return -1; // byte[] payloads map to PostgreSQL BYTEA (Types.BINARY, not VARBINARY)
    }

    try {
      byte[] zipBytes;
      try (ByteArrayOutputStream baos = new ByteArrayOutputStream();
          ZipOutputStream zipOut = new ZipOutputStream(baos)) {
        ZipEntry zipEntry = new ZipEntry("reservations.json");
        zipOut.putNextEntry(zipEntry);
        zipOut.write(reservationBytes, 0, reservationBytes.length);
        zipOut.closeEntry();
        zipOut.finish();
        zipBytes = baos.toByteArray();
      }

      // verify zip content is readable
      boolean valid = true;
      try (ZipInputStream zin = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
        while (zin.getNextEntry() != null) {
          zin.closeEntry();
        }
      } catch (IOException e) {
        valid = false;
      }

      if (valid) {
        BlobInfo blobInfo = BlobInfo.newBuilder(BlobId.of(bucketName, objectName))
            .setContentType("application/zip").build();
        try (Storage storage = StorageOptions.getDefaultInstance().getService()) {
          storage.create(blobInfo, zipBytes);
        }
        return 0;
      }
    } catch (IOException e) {
      e.printStackTrace();
    } catch (Throwable e) {
      e.printStackTrace();
    }
    return -1;
  }

}
