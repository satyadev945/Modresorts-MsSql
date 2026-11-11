package com.acme.modres;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.logging.Logger;
import java.util.zip.ZipEntry;
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

import com.acme.modres.util.DateUtil;
import com.acme.modres.util.ZipValidator;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;

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
          Date fromDate = DateUtil.parse(reservation.getFromDate());
          Date toDate = DateUtil.parse(reservation.getToDate());
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
    final String entryName = "reservations.json";
    byte[] sourceBytes = IOUtils.getBytesFromRelativePath(entryName);

    // Azure Blob Storage configuration (externalized via environment variables)
    String connectionString = System.getenv("AZURE_STORAGE_CONNECTION_STRING");
    String containerName = System.getenv().getOrDefault("AZURE_STORAGE_CONTAINER_NAME", "reservations");
    String blobName = System.getenv().getOrDefault("AZURE_STORAGE_BLOB_NAME", "reservations.zip");

    try {
      if (connectionString == null || connectionString.isEmpty()) {
        logger.severe("AZURE_STORAGE_CONNECTION_STRING is not configured");
        return -1;
      }

      // Build the zip archive in memory instead of writing to the local file system
      if (sourceBytes == null) {
        logger.severe("Unable to load resource " + entryName);
        return -1;
      }
      byte[] zipBytes;
      try (ByteArrayOutputStream baos = new ByteArrayOutputStream();
          ZipOutputStream zipOut = new ZipOutputStream(baos)) {
        zipOut.putNextEntry(new ZipEntry(entryName));
        zipOut.write(sourceBytes, 0, sourceBytes.length);
        zipOut.closeEntry();
        zipOut.finish();
        zipBytes = baos.toByteArray();
      }

      // Upload the zip to Azure Blob Storage
      BlobServiceClient serviceClient = new BlobServiceClientBuilder().connectionString(connectionString)
          .buildClient();
      BlobContainerClient containerClient = serviceClient.getBlobContainerClient(containerName);
      if (!containerClient.exists()) {
        containerClient.create();
      }
      BlobClient blobClient = containerClient.getBlobClient(blobName);
      try (ByteArrayInputStream zipIn = new ByteArrayInputStream(zipBytes)) {
        blobClient.upload(zipIn, zipBytes.length, true);
      }

      // verify zip
      ZipValidator zipValidator = new ZipValidator(blobClient.downloadContent().toBytes());
      if (zipValidator.isValid()) {
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
