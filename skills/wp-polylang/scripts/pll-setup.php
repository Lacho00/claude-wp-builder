<?php
/**
 * Verify Polylang is usable and create any missing language.
 *
 * Usage: wp eval-file pll-setup.php <source_lang> <target_lang>
 *
 * Installing the plugin itself is WP-CLI's job and stays in the command doc;
 * this script fails with that exact command line when the plugin is absent.
 */

require_once __DIR__ . '/pll-lib.php';

list( $source, $target ) = pllx_args( 2, 'pll-setup.php <source_lang> <target_lang>' );

pllx_require_polylang();

if ( $source === $target ) {
	pllx_fail( "Source and target language are both '$source'." );
}

/**
 * Preferred locales.
 *
 * Polylang's predefined list is searched by language code and returns its FIRST
 * match, which for 'en' is en_AU and for 'es' is es_AR — not what a site
 * usually wants. These defaults win when present.
 */
$preferred = array(
	'en' => 'en_US', 'es' => 'es_ES', 'fr' => 'fr_FR', 'de' => 'de_DE',
	'it' => 'it_IT', 'pt' => 'pt_PT', 'nl' => 'nl_NL', 'ca' => 'ca',
);

function pllx_add_language( $code, $preferred ) {
	if ( ! class_exists( 'PLL_Settings' ) || ! is_callable( array( 'PLL_Settings', 'get_predefined_languages' ) ) ) {
		pllx_fail( "Cannot read Polylang's predefined language list; add '$code' from the admin instead." );
	}

	$predefined = PLL_Settings::get_predefined_languages();
	$want       = isset( $preferred[ $code ] ) ? $preferred[ $code ] : null;
	$chosen     = null;

	foreach ( $predefined as $entry ) {
		$entry_code   = isset( $entry['code'] ) ? $entry['code'] : '';
		$entry_locale = isset( $entry['locale'] ) ? $entry['locale'] : '';
		if ( $want && $entry_locale === $want ) {
			$chosen = $entry;
			break;
		}
		if ( ! $chosen && $entry_code === $code ) {
			$chosen = $entry; // fallback: first match by code
		}
	}

	if ( ! $chosen ) {
		pllx_fail( "'$code' is not a language Polylang recognises." );
	}

	$existing = PLL()->model->get_languages_list();
	$res      = PLL()->model->add_language( array(
		'name'       => $chosen['name'],
		'slug'       => $code,
		'locale'     => $chosen['locale'],
		'rtl'        => ! empty( $chosen['dir'] ) && 'rtl' === $chosen['dir'] ? 1 : 0,
		'term_group' => count( $existing ),
		'flag'       => isset( $chosen['flag'] ) ? $chosen['flag'] : '',
	) );

	if ( is_wp_error( $res ) ) {
		pllx_fail( "Could not create language '$code': " . $res->get_error_message() );
	}

	pllx_info( "  created language $code ({$chosen['locale']})" );
}

$configured = (array) pll_languages_list();
foreach ( array( $source, $target ) as $code ) {
	if ( ! in_array( $code, $configured, true ) ) {
		pllx_info( "Language '$code' missing" );
		pllx_add_language( $code, $preferred );
	}
}

// Re-read: add_language() invalidates the cached list.
PLL()->model->clean_languages_cache();
$configured = (array) pll_languages_list();

foreach ( array( $source, $target ) as $code ) {
	if ( ! in_array( $code, $configured, true ) ) {
		pllx_fail( "Language '$code' still missing after creation." );
	}
}

pllx_info( "Polylang ready: source=$source target=$target" );
pllx_info( 'Configured languages: ' . implode( ', ', $configured ) );
pllx_info( 'Default language: ' . pll_default_language() );
