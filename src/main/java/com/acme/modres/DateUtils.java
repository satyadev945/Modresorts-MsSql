package com.acme.modres;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

/**
 * Timezone-agnostic date parsing. All reservation dates are interpreted in a
 * fixed, configurable zone (default UTC, override with APP_TIMEZONE env var)
 * instead of the server-local default timezone, so behaviour is identical
 * across containers/regions.
 */
public final class DateUtils {

  private static final String ZONE_ID = System.getenv().getOrDefault("APP_TIMEZONE", "UTC");

  private DateUtils() {
  }

  /** Creates a new (non thread-safe) formatter pinned to the configured zone. */
  public static SimpleDateFormat newFormat() {
    SimpleDateFormat format = new SimpleDateFormat(Constants.DATA_FORMAT, Locale.ROOT);
    format.setTimeZone(TimeZone.getTimeZone(ZONE_ID));
    return format;
  }

  public static Date parse(String value) throws ParseException {
    return newFormat().parse(value);
  }
}
