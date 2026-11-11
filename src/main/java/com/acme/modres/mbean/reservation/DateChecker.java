package com.acme.modres.mbean.reservation;

import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.List;

public class DateChecker implements Runnable {
  ReservationCheckerData data;
  List<Reservation> reservations;

  public DateChecker(ReservationCheckerData data) {
    this.data = data;
    this.reservations = data.getReservationList().getReservations();
  }

  public void run() {
    for (int i = 0; i < reservations.size(); i++) {
      Reservation reservation = reservations.get(i);
      Instant selectedDate = data.getSelectedDate();

      try {
        Instant fromDate = ReservationCheckerData.parseDate(reservation.getFromDate());
        Instant toDate = ReservationCheckerData.parseDate(reservation.getToDate());
        if (selectedDate.isAfter(fromDate) && selectedDate.isBefore(toDate)) {
          data.setAvailablility(false);
          break;
        }
      } catch (DateTimeParseException ex) {
        ex.printStackTrace();
      }
    }
    data.setAvailablility(true);
  }
}
