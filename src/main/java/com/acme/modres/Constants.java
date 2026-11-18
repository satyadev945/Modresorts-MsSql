package com.acme.modres;

public class Constants {

  public static final String BARCELONA = "Barcelona";
  public static final String CORK = "Cork";
  public static final String MIAMI = "Miami";
  public static final String SAN_FRANCISCO = "San_Francisco";
  public final static String PARIS = "Paris";
  public static final String LAS_VEGAS = "Las_Vegas";

  public final static String[] SUPPORTED_CITIES = { PARIS, LAS_VEGAS, SAN_FRANCISCO, MIAMI, CORK, BARCELONA };

  public final static String BACELONA_WEATHER_FILE = "barcelona.json";
  public final static String CORK_WEATHER_FILE = "cork.json";
  public final static String LAS_VEGAS_WEATHER_FILE = "nv.json";
  public final static String MIAMI_WEATHER_FILE = "miami.json";
  public final static String PARIS_WEATHER_FILE = "paris.json";
  public final static String SAN_FRANCESCO_WEATHER_FILE = "sanfran.json";

  // constants used to construct Weather Underground API
  public final static String WUNDERGROUND_API_PREFIX = "http://api.wunderground.com/api/";
  public final static String WUNDERGROUND_API_PART = "/forecast/geolookup/conditions/q/";

  public final static String DATA_FORMAT = "MM/dd/yyyy";

  /**
   * Returns a date formatter pinned to UTC so date parsing does not depend on the
   * server-local timezone (consistent across distributed Azure instances/regions).
   * SimpleDateFormat is not thread-safe, so a new instance is returned on each call.
   */
  public static java.text.SimpleDateFormat newDateFormat() {
    java.text.SimpleDateFormat fmt = new java.text.SimpleDateFormat(DATA_FORMAT);
    fmt.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
    return fmt;
  }

}
