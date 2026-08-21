<?php
/**
 * Shared helpers for the wp-polylang scripts.
 *
 * Loaded with `require_once __DIR__ . '/pll-lib.php';`. __DIR__ resolves
 * correctly under `wp eval-file` despite its eval() wrapper.
 *
 * PHP 7.4 floor: no match expressions, no union types.
 */

if ( ! defined( 'PLLX_HASH_META' ) ) {
	// Meta key on the TRANSLATION holding the hash of the SOURCE payload.
	define( 'PLLX_HASH_META', '_pll_src_hash' );
}

/**
 * Bridge wp eval-file's $args into $GLOBALS.
 *
 * `wp eval-file` evaluates the target script inside a WP-CLI method's local
 * scope, so the $args array it populates with positional arguments is a
 * local variable there — it is never written to $GLOBALS. pllx_args() below
 * reads $args with `global $args;`, which only ever sees $GLOBALS, so
 * without this bridge it always sees an unset value and every script fails
 * its own usage check. This statement runs as top-level code required into
 * that same local scope (require does not open a new scope for top-level
 * statements), so it is the only place that can see the real local $args
 * and mirror it across for pllx_args() to find.
 */
if ( isset( $args ) && ! isset( $GLOBALS['args'] ) ) {
	$GLOBALS['args'] = $args;
}

function pllx_info( $msg ) { echo "[+] $msg\n"; }
function pllx_warn( $msg ) { echo "[!] $msg\n"; }

/** Report and exit non-zero. Never fail silently. */
function pllx_fail( $msg ) {
	fwrite( STDERR, "[x] $msg\n" );
	exit( 1 );
}

/** Read exactly $count positional arguments, or explain the usage and exit. */
function pllx_args( $count, $usage ) {
	global $args;
	$given = is_array( $args ) ? $args : array();
	if ( count( $given ) < $count ) {
		pllx_fail( "Usage: wp eval-file $usage" );
	}
	return array_slice( $given, 0, $count );
}

function pllx_require_polylang() {
	if ( ! function_exists( 'pll_languages_list' ) ) {
		pllx_fail( "Polylang is not active. Run: wp plugin install polylang --activate" );
	}
}

function pllx_require_langs( $source, $target ) {
	$langs = (array) pll_languages_list();
	foreach ( array( $source, $target ) as $l ) {
		if ( ! in_array( $l, $langs, true ) ) {
			pllx_fail( "Language '$l' is not configured. Configured: " . implode( ', ', $langs ) );
		}
	}
	if ( $source === $target ) {
		pllx_fail( "Source and target language are both '$source'." );
	}
}

/**
 * True for the site's date/time format strings.
 *
 * Compared against the actual option values rather than pattern-matched: a
 * heuristic on the shape of a format string produces false positives on short
 * real content, and this comparison is exact.
 */
function pllx_is_date_format( $s ) {
	return in_array( $s, array( get_option( 'date_format' ), get_option( 'time_format' ) ), true );
}

/** The translatable payload of a post. Used for both export and hashing. */
function pllx_post_payload( $post_id ) {
	$p = get_post( $post_id );
	if ( ! $p ) {
		return array( 'fields' => array(), 'acf' => array() );
	}
	return array(
		'fields' => array(
			'post_title'   => $p->post_title,
			'post_content' => $p->post_content,
			'post_excerpt' => $p->post_excerpt,
			'post_name'    => $p->post_name,
		),
		'acf'    => pllx_acf_payload( $post_id ),
	);
}

/** The translatable payload of a term. */
function pllx_term_payload( $term_id, $taxonomy ) {
	$t = get_term( $term_id, $taxonomy );
	if ( ! $t || is_wp_error( $t ) ) {
		return array( 'fields' => array(), 'acf' => array() );
	}
	return array(
		'fields' => array(
			'name'        => $t->name,
			'description' => $t->description,
			'slug'        => $t->slug,
		),
		'acf'    => array(),
	);
}

/**
 * Flatten a post's translatable ACF values to dot notation.
 *
 * Only text-bearing types are included; images, URLs, numbers and booleans are
 * copied verbatim by the importer and never sent for translation.
 *
 * Ceiling: one level of nesting inside groups and repeaters. Deeper structures
 * are not walked. Widen pllx_acf_walk() if a project needs it.
 */
function pllx_acf_payload( $post_id ) {
	if ( ! function_exists( 'get_field_objects' ) ) {
		return array();
	}
	$objects = get_field_objects( $post_id );
	if ( ! is_array( $objects ) ) {
		return array();
	}
	$out = array();
	pllx_acf_walk( $objects, $out );
	return $out;
}

function pllx_acf_walk( $objects, &$out ) {
	$text = array( 'text', 'textarea', 'wysiwyg' );

	foreach ( $objects as $name => $obj ) {
		$type = isset( $obj['type'] ) ? $obj['type'] : '';
		$val  = isset( $obj['value'] ) ? $obj['value'] : null;
		$subs = isset( $obj['sub_fields'] ) && is_array( $obj['sub_fields'] ) ? $obj['sub_fields'] : array();

		if ( in_array( $type, $text, true ) ) {
			if ( is_string( $val ) && '' !== $val ) {
				$out[ $name ] = $val;
			}
			continue;
		}

		if ( 'group' === $type && is_array( $val ) ) {
			foreach ( $subs as $sub ) {
				$sname = $sub['name'];
				if ( in_array( $sub['type'], $text, true )
					&& isset( $val[ $sname ] ) && is_string( $val[ $sname ] ) && '' !== $val[ $sname ] ) {
					$out[ "$name.$sname" ] = $val[ $sname ];
				}
			}
			continue;
		}

		if ( 'repeater' === $type && is_array( $val ) ) {
			foreach ( $val as $i => $row ) {
				if ( ! is_array( $row ) ) {
					continue;
				}
				foreach ( $subs as $sub ) {
					$sname = $sub['name'];
					if ( in_array( $sub['type'], $text, true )
						&& isset( $row[ $sname ] ) && is_string( $row[ $sname ] ) && '' !== $row[ $sname ] ) {
						$out[ "$name.$i.$sname" ] = $row[ $sname ];
					}
				}
			}
		}
	}
}

/**
 * Deterministic hash of a payload.
 *
 * Keys are sorted so that a change in field order never registers as drift.
 * export and verify MUST both call this — a second implementation would drift
 * and make verify report false staleness on correctly translated content.
 */
function pllx_hash( $payload ) {
	$f = isset( $payload['fields'] ) ? $payload['fields'] : array();
	$a = isset( $payload['acf'] ) ? $payload['acf'] : array();
	ksort( $f );
	ksort( $a );
	return hash( 'sha256', wp_json_encode( array( 'fields' => $f, 'acf' => $a ) ) );
}
