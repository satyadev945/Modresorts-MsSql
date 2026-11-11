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

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
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
          Date fromDate = DateUtils.parse(reservation.getFromDate());
          Date toDate = DateUtils.parse(reservation.getToDate());
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
    byte[] reservationBytes = IOUtils.getBytesFromRelativePath("reservations.json");
    if (reservationBytes == null) {
      logger.severe("reservations.json could not be loaded from classpath");
      return -1;
    }

    // Azure Blob Storage configuration (externalized via environment variables)
    String connectionString = System.getenv("AZURE_STORAGE_CONNECTION_STRING");
    String containerName = System.getenv().getOrDefault("AZURE_STORAGE_CONTAINER_NAME", "reservations");
    String blobName = System.getenv().getOrDefault("AZURE_STORAGE_RESERVATIONS_BLOB_NAME", "reservations.zip");

    try {
      // build the zip in memory instead of writing to a host file system path
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

      // verify zip
      boolean valid = false;
      try (ZipInputStream zis = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
        valid = zis.getNextEntry() != null;
      }
      if (!valid) {
        return -1;
      }

      // upload zip to Azure Blob Storage
      BlobServiceClientBuilder builder = new BlobServiceClientBuilder();
      if (connectionString != null && !connectionString.isEmpty()) {
        builder.connectionString(connectionString);
      } else {
        String accountName = System.getenv("AZURE_STORAGE_ACCOUNT_NAME");
        if (accountName == null || accountName.isEmpty()) {
          logger.severe("Azure Storage is not configured (AZURE_STORAGE_CONNECTION_STRING or AZURE_STORAGE_ACCOUNT_NAME)");
          return -1;
        }
        builder.endpoint("https://" + accountName + ".blob.core.windows.net")
            .credential(new DefaultAzureCredentialBuilder().build());
      }
      BlobContainerClient containerClient = builder.buildClient().getBlobContainerClient(containerName);
      if (!containerClient.exists()) {
        containerClient.create();
      }
      BlobClient blobClient = containerClient.getBlobClient(blobName);
      try (ByteArrayInputStream uploadStream = new ByteArrayInputStream(zipBytes)) {
        blobClient.upload(uploadStream, zipBytes.length, true);
      }
      return 0;
    } catch (IOException e) {
      e.printStackTrace();
    } catch (Throwable e) {
      e.printStackTrace();
    }
    return -1;
  }

}
