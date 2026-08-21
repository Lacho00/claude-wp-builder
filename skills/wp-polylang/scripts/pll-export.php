<?php
/**
 * Emit a manifest of everything missing or stale in the target language.
 *
 * Usage: wp eval-file pll-export.php <source_lang> <target_lang> <out.json>
 *
 * Skip logic, per item: no counterpart -> include with target_id null; a
 * counterpart whose stored source hash still matches -> skip, costing no
 * tokens; a counterpart whose hash differs -> include with its target_id so the
 * importer updates in place.
 */

require_once __DIR__ . '/pll-lib.php';

list( $source, $target, $out_path ) = pllx_args( 3, 'pll-export.php <source_lang> <target_lang> <out.json>' );

pllx_require_polylang();
pllx_require_langs( $source, $target );

$items   = array();
$skipped = 0;

/** Decide whether an item needs work. Returns [include(bool), target_id|null]. */
function pllx_needs_work( $translations, $target, $hash, $meta_reader ) {
	if ( empty( $translations[ $target ] ) ) {
		return array( true, null );
	}
	$target_id = (int) $translations[ $target ];
	$stored    = call_user_func( $meta_reader, $target_id );
	if ( $stored === $hash ) {
		return array( false, $target_id );
	}
	return array( true, $target_id );
}

// ── Posts (every translatable post type Polylang is configured for) ──────────
$post_types = array_keys( PLL()->model->get_translated_post_types() );

$posts = get_posts( array(
	'post_type'        => $post_types,
	'post_status'      => array( 'publish', 'draft', 'pending', 'private' ),
	'numberposts'      => -1,
	'lang'             => $source,
	'fields'           => 'ids',
	'suppress_filters' => false,
) );

foreach ( $posts as $post_id ) {
	if ( pll_get_post_language( $post_id ) !== $source ) {
		continue;
	}
	$payload = pllx_post_payload( $post_id );
	$hash    = pllx_hash( $payload );

	list( $include, $target_id ) = pllx_needs_work(
		pll_get_post_translations( $post_id ),
		$target,
		$hash,
		function ( $id ) { return get_post_meta( $id, PLLX_HASH_META, true ); }
	);

	if ( ! $include ) {
		$skipped++;
		continue;
	}

	$items[] = array(
		'id'        => 'post:' . $post_id,
		'kind'      => 'post',
		'post_type' => get_post_type( $post_id ),
		'source_id' => (int) $post_id,
		'target_id' => $target_id,
		'hash'      => $hash,
		'fields'    => $payload['fields'],
		'acf'       => $payload['acf'],
	);
}

// ── Terms ───────────────────────────────────────────────────────────────────
$taxonomies = array_keys( PLL()->model->get_translated_taxonomies() );

foreach ( $taxonomies as $taxonomy ) {
	$terms = get_terms( array( 'taxonomy' => $taxonomy, 'hide_empty' => false, 'lang' => $source ) );
	if ( is_wp_error( $terms ) ) {
		pllx_warn( "Skipping taxonomy '$taxonomy': " . $terms->get_error_message() );
		continue;
	}
	foreach ( $terms as $term ) {
		if ( pll_get_term_language( $term->term_id ) !== $source ) {
			continue;
		}
		$payload = pllx_term_payload( $term->term_id, $taxonomy );
		$hash    = pllx_hash( $payload );

		list( $include, $target_id ) = pllx_needs_work(
			pll_get_term_translations( $term->term_id ),
			$target,
			$hash,
			function ( $id ) { return get_term_meta( $id, PLLX_HASH_META, true ); }
		);

		if ( ! $include ) {
			$skipped++;
			continue;
		}

		$items[] = array(
			'id'        => 'term:' . $taxonomy . ':' . $term->term_id,
			'kind'      => 'term',
			'taxonomy'  => $taxonomy,
			'source_id' => (int) $term->term_id,
			'target_id' => $target_id,
			'hash'      => $hash,
			'fields'    => $payload['fields'],
		);
	}
}

// ── Registered strings ──────────────────────────────────────────────────────
if ( class_exists( 'PLL_Admin_Strings' ) ) {
	foreach ( PLL_Admin_Strings::get_strings() as $entry ) {
		$value   = isset( $entry['string'] ) ? $entry['string'] : '';
		$context = isset( $entry['context'] ) ? $entry['context'] : 'polylang';

		if ( '' === $value || pllx_is_date_format( $value ) ) {
			$skipped++;
			continue;
		}

		$hash = pllx_hash( array( 'fields' => array( 'value' => $value ), 'acf' => array() ) );

		$items[] = array(
			'id'      => 'string:' . $context . ':' . md5( $value ),
			'kind'    => 'string',
			'context' => $context,
			'hash'    => $hash,
			'fields'  => array( 'value' => $value ),
		);
	}
}

$manifest = array(
	'source_lang' => $source,
	'target_lang' => $target,
	'site_url'    => home_url(),
	'items'       => $items,
);

$json = wp_json_encode( $manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES );
if ( false === $json ) {
	pllx_fail( 'Could not encode the manifest as JSON: ' . json_last_error_msg() );
}
if ( false === file_put_contents( $out_path, $json ) ) {
	pllx_fail( "Could not write the manifest to '$out_path'." );
}

pllx_info( sprintf( 'Exported %d item(s), skipped %d already current.', count( $items ), $skipped ) );
pllx_info( "Manifest: $out_path" );
