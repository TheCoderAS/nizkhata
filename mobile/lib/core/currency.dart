// The currencies a workspace can keep its books in.
//
// A workspace has exactly one currency, chosen when it is created and never
// changed afterwards (the Firestore rules enforce that). Everything about how a
// figure is written follows from it: the symbol, how many decimal places the
// currency has, and how digits are grouped. Keeping all of that here, keyed by
// the ISO code, means no screen has to know which country it is in.

/// How long numbers are broken up.
///
/// South Asian currencies group in lakhs and crores (12,34,56,789.00) and are
/// abbreviated the same way (12.3L, 1.2Cr). Everyone else groups in thousands
/// (123,456,789.00) and abbreviates in thousands, millions and billions.
enum DigitGrouping { southAsian, international }

class CurrencySpec {
  /// ISO 4217 code, e.g. `INR`.
  final String code;
  final String name;

  /// What goes in front of the figure, e.g. `₹`, `$`, `AED `.
  final String symbol;

  /// Minor units: 2 for most, 0 for the yen, 3 for the Kuwaiti dinar.
  final int decimals;
  final DigitGrouping grouping;

  /// Month the financial year usually starts in where this currency is used.
  /// Only a default for new workspaces; each workspace can change its own.
  final int defaultFyStartMonth;

  const CurrencySpec(
    this.code,
    this.name,
    this.symbol, {
    this.decimals = 2,
    this.grouping = DigitGrouping.international,
    this.defaultFyStartMonth = 1,
  });

  /// The intl locale whose number pattern gives this currency's grouping.
  /// Only the grouping is taken from it; the symbol and decimals are ours.
  String get numberLocale => grouping == DigitGrouping.southAsian ? 'en_IN' : 'en_US';

  /// The India-specific parts of the app (IFSC, CIF, TDS, the India tax pack)
  /// belong to INR workspaces only.
  bool get isIndian => code == 'INR';
}

/// Offered when creating a workspace. Ordered by likely use for this app's
/// users, then broadly by region; the picker searches by code and name.
const kCurrencies = <CurrencySpec>[
  CurrencySpec('INR', 'Indian rupee', '₹', grouping: DigitGrouping.southAsian, defaultFyStartMonth: 4),
  CurrencySpec('USD', 'US dollar', '\$'),
  CurrencySpec('EUR', 'Euro', '€'),
  CurrencySpec('GBP', 'British pound', '£', defaultFyStartMonth: 4),
  CurrencySpec('AED', 'UAE dirham', 'AED '),
  CurrencySpec('SAR', 'Saudi riyal', 'SAR '),
  CurrencySpec('QAR', 'Qatari riyal', 'QAR '),
  CurrencySpec('KWD', 'Kuwaiti dinar', 'KWD ', decimals: 3, defaultFyStartMonth: 4),
  CurrencySpec('BHD', 'Bahraini dinar', 'BHD ', decimals: 3),
  CurrencySpec('OMR', 'Omani rial', 'OMR ', decimals: 3),
  CurrencySpec('SGD', 'Singapore dollar', 'S\$'),
  CurrencySpec('AUD', 'Australian dollar', 'A\$', defaultFyStartMonth: 7),
  CurrencySpec('NZD', 'New Zealand dollar', 'NZ\$', defaultFyStartMonth: 4),
  CurrencySpec('CAD', 'Canadian dollar', 'C\$'),
  CurrencySpec('CHF', 'Swiss franc', 'CHF '),
  CurrencySpec('JPY', 'Japanese yen', '¥', decimals: 0, defaultFyStartMonth: 4),
  CurrencySpec('CNY', 'Chinese yuan', 'CN¥'),
  CurrencySpec('HKD', 'Hong Kong dollar', 'HK\$', defaultFyStartMonth: 4),
  CurrencySpec('KRW', 'South Korean won', '₩', decimals: 0),
  CurrencySpec('MYR', 'Malaysian ringgit', 'RM '),
  CurrencySpec('THB', 'Thai baht', '฿'),
  CurrencySpec('IDR', 'Indonesian rupiah', 'Rp '),
  CurrencySpec('PHP', 'Philippine peso', '₱'),
  CurrencySpec('PKR', 'Pakistani rupee', 'Rs ', grouping: DigitGrouping.southAsian, defaultFyStartMonth: 7),
  CurrencySpec('BDT', 'Bangladeshi taka', '৳', grouping: DigitGrouping.southAsian, defaultFyStartMonth: 7),
  CurrencySpec('NPR', 'Nepalese rupee', 'Rs ', grouping: DigitGrouping.southAsian, defaultFyStartMonth: 7),
  CurrencySpec('LKR', 'Sri Lankan rupee', 'Rs '),
  CurrencySpec('ZAR', 'South African rand', 'R ', defaultFyStartMonth: 3),
  CurrencySpec('NGN', 'Nigerian naira', '₦'),
  CurrencySpec('KES', 'Kenyan shilling', 'KSh ', defaultFyStartMonth: 7),
  CurrencySpec('BRL', 'Brazilian real', 'R\$'),
  CurrencySpec('MXN', 'Mexican peso', 'MX\$'),
];

final Map<String, CurrencySpec> _byCode = {for (final c in kCurrencies) c.code: c};

/// The spec for [code]. An unknown code still formats sensibly — the code as
/// its own symbol, two decimals, international grouping — so a workspace made
/// with a currency later dropped from the list never renders as garbage.
CurrencySpec currencySpec(String code) =>
    _byCode[code.toUpperCase()] ?? CurrencySpec(code.toUpperCase(), code.toUpperCase(), '${code.toUpperCase()} ');

/// A suggestion for the currency picker, from the phone's country.
///
/// Only ever a preselection: the currency is permanent once chosen, so it is
/// always confirmed by the person, never applied on this guess alone. (Phone
/// locale is a poor signal in India in particular, where many phones are set to
/// English (US).)
String? currencyForCountry(String? countryCode) {
  if (countryCode == null) return null;
  const map = <String, String>{
    'IN': 'INR', 'US': 'USD', 'GB': 'GBP', 'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR',
    'KW': 'KWD', 'BH': 'BHD', 'OM': 'OMR', 'SG': 'SGD', 'AU': 'AUD', 'NZ': 'NZD',
    'CA': 'CAD', 'CH': 'CHF', 'JP': 'JPY', 'CN': 'CNY', 'HK': 'HKD', 'KR': 'KRW',
    'MY': 'MYR', 'TH': 'THB', 'ID': 'IDR', 'PH': 'PHP', 'PK': 'PKR', 'BD': 'BDT',
    'NP': 'NPR', 'LK': 'LKR', 'ZA': 'ZAR', 'NG': 'NGN', 'KE': 'KES', 'BR': 'BRL',
    'MX': 'MXN',
    // The euro area.
    'DE': 'EUR', 'FR': 'EUR', 'IT': 'EUR', 'ES': 'EUR', 'NL': 'EUR', 'BE': 'EUR',
    'AT': 'EUR', 'IE': 'EUR', 'PT': 'EUR', 'FI': 'EUR', 'GR': 'EUR', 'LU': 'EUR',
  };
  return map[countryCode.toUpperCase()];
}

/// The currency the app is currently keeping books in, for code that has no
/// workspace to ask — chiefly [roundMoney], which feeds dozens of pure
/// calculations. Set whenever the active workspace changes. Defaults to INR so
/// that tests, and any code that runs before a workspace loads, behave exactly
/// as the app always has.
class MoneyContext {
  MoneyContext._();
  static CurrencySpec _spec = currencySpec('INR');
  static CurrencySpec get spec => _spec;
  static int get decimals => _spec.decimals;
  static set currency(String code) => _spec = currencySpec(code);
}
