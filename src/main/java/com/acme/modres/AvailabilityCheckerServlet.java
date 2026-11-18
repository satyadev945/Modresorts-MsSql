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
import java.text.SimpleDateFormat;
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

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobContainerClientBuilder;

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
          Date fromDate = Constants.newDateFormat().parse(reservation.getFromDate());
          Date toDate = Constants.newDateFormat().parse(reservation.getToDate());
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
    try {
      byte[] reservationBytes = IOUtils.readResourceBytes("reservations.json");

      // Build the archive fully in memory (no local file system writes)
      ByteArrayOutputStream zipBuffer = new ByteArrayOutputStream();
      try (ZipOutputStream zipOut = new ZipOutputStream(zipBuffer)) {
        zipOut.putNextEntry(new ZipEntry("reservations.json"));
        zipOut.write(reservationBytes, 0, reservationBytes.length);
        zipOut.closeEntry();
      }
      byte[] zipBytes = zipBuffer.toByteArray();

      // verify zip (byte[] is compatible with PostgreSQL BYTEA if persisted to a DB)
      boolean valid = false;
      try (ZipInputStream zipIn = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
        valid = zipIn.getNextEntry() != null;
      }

      if (valid) {
        // Persist the archive to Azure Blob Storage
        String connectionString = System.getenv("AZURE_STORAGE_CONNECTION_STRING");
        String containerName = System.getenv("AZURE_STORAGE_CONTAINER_NAME");
        if (containerName == null || containerName.isEmpty()) {
          containerName = "reservations";
        }
        String blobName = System.getenv("AZURE_STORAGE_BLOB_NAME");
        if (blobName == null || blobName.isEmpty()) {
          blobName = "reservations.zip";
        }
        if (connectionString == null || connectionString.isEmpty()) {
          logger.severe("AZURE_STORAGE_CONNECTION_STRING is not configured");
          return -1;
        }

        BlobContainerClient containerClient = new BlobContainerClientBuilder()
            .connectionString(connectionString)
            .containerName(containerName)
            .buildClient();
        if (!containerClient.exists()) {
          containerClient.create();
        }
        BlobClient blobClient = containerClient.getBlobClient(blobName);
        try (ByteArrayInputStream uploadStream = new ByteArrayInputStream(zipBytes)) {
          blobClient.upload(uploadStream, zipBytes.length, true);
        }
        return 0;
      }
    } catch (Throwable e) {
      e.printStackTrace();
    }
    return -1;
  }

}
