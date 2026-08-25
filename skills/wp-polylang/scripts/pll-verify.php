<?php
/**
 * Audit a translated site.
 *
 * Usage: wp eval-file pll-verify.php <source_lang> <target_lang>
 *
 * Exits 1 when any hard check fails. Costs no tokens, so it is also the way to
 * audit a site translated months ago.
 */

require_once __DIR__ . '/pll-lib.php';

list( $source, $target ) = pllx_args( 2, 'pll-verify.php <source_lang> <target_lang>' );

pllx_require_polylang();
pllx_require_langs( $source, $target );

$failures = array();
$warnings = array();
$counts   = array( 'posts' => 0, 'terms' => 0, 'menu_items' => 0, 'internal_links' => 0 );

// ── 1. Menu items point at target-language objects ──────────────────────────
$theme   = get_stylesheet();
$options = get_option( 'polylang' );
$locs    = isset( $options['nav_menus'][ $theme ] ) ? $options['nav_menus'][ $theme ] : array();

foreach ( $locs as $location => $per_lang ) {
	// A location with no SOURCE menu is not part of this source/target pair and
	// there is nothing to have translated -- a site with a third language may
	// legitimately assign a location in that language alone. Demanding a target
	// menu there turns an untouched location into a hard failure and calls a
	// correct site broken. pll-export.php gates the same way before it exports.
	if ( empty( $per_lang[ $source ] ) ) {
		continue;
	}
	if ( empty( $per_lang[ $target ] ) ) {
		$failures[] = "menu location '$location' has no $target menu";
		continue;
	}
	foreach ( (array) wp_get_nav_menu_items( (int) $per_lang[ $target ] ) as $mi ) {
		$counts['menu_items']++;
		if ( 'post_type' === $mi->type ) {
			$lang = pll_get_post_language( (int) $mi->object_id );
			if ( $lang !== $target ) {
				$failures[] = "menu item '{$mi->title}' points at a '" . ( $lang ? $lang : 'none' ) . "' post ({$mi->object_id}), expected '$target'";
			}
		} elseif ( 'taxonomy' === $mi->type ) {
			$lang = pll_get_term_language( (int) $mi->object_id );
			if ( $lang !== $target ) {
				$failures[] = "menu item '{$mi->title}' points at a '" . ( $lang ? $lang : 'none' ) . "' term ({$mi->object_id}), expected '$target'";
			}
		} elseif ( 'custom' === $mi->type ) {
			// Ruling T9-F: a 'custom' item carries a literal href, not an
			// object id + type this check could otherwise resolve through
			// pll_get_post_translations() -- exactly what a duplicated menu
			// produces, and exactly the gap the link-rewrite pass in
			// pll-import.php closes. Only checked when the URL actually
			// resolves to a post; an item that is genuinely a mailto:,
			// external site, or non-post internal URL has no per-language
			// object to be wrong about.
			$found_id = pllx_url_to_postid( $mi->url );
			if ( $found_id ) {
				$lang = pll_get_post_language( $found_id );
				if ( $lang !== $target ) {
					$failures[] = "menu item '{$mi->title}' (custom URL) points at a '" . ( $lang ? $lang : 'none' ) . "' post ($found_id), expected '$target'";
				}
			}
		}
	}
}

// ── 2-7. Posts ──────────────────────────────────────────────────────────────
$post_types = array_keys( PLL()->model->get_translated_post_types() );
$seen_slugs = array();
$unassigned = array(); // post_type or taxonomy name => count with no language at all.

// No 'lang' filter: an object with no language matches no language, so filtering
// here would hide exactly the objects most worth reporting. Classify explicitly,
// the same way pll-export.php does.
$all_posts = get_posts( array(
	'post_type'        => $post_types,
	'post_status'      => array( 'publish', 'draft', 'pending', 'private', 'inherit' ),
	'numberposts'      => -1,
	'fields'           => 'ids',
	'suppress_filters' => false,
) );

$source_posts = array();
$target_posts = array();

foreach ( $all_posts as $post_id ) {
	$lang = pll_get_post_language( $post_id );
	if ( ! $lang ) {
		$pt = get_post_type( $post_id );
		$unassigned[ $pt ] = isset( $unassigned[ $pt ] ) ? $unassigned[ $pt ] + 1 : 1;
	} elseif ( $lang === $source ) {
		$source_posts[] = $post_id;
	} elseif ( $lang === $target ) {
		$target_posts[] = $post_id;
	}
}

foreach ( $source_posts as $source_id ) {
	$counts['posts']++;
	$translations = pll_get_post_translations( $source_id );

	if ( empty( $translations[ $target ] ) ) {
		$failures[] = "post $source_id has no $target counterpart";
		continue;
	}

	$target_id = (int) $translations[ $target ];

	if ( ! get_post( $target_id ) ) {
		$failures[] = "post $source_id points at $target_id, which does not exist";
		continue;
	}

	// 3. Correct language on the counterpart.
	$actual = pll_get_post_language( $target_id );
	if ( $actual !== $target ) {
		$failures[] = "post $target_id has language '" . ( $actual ? $actual : 'none' ) . "', expected '$target'";
	}

	// 2. The group is symmetric.
	$back = pll_get_post_translations( $target_id );
	if ( (int) ( isset( $back[ $source ] ) ? $back[ $source ] : 0 ) !== (int) $source_id ) {
		$failures[] = "translation group for $source_id/$target_id is not symmetric";
	}

	// 5. Stored hash still matches the source.
	$stored = get_post_meta( $target_id, PLLX_HASH_META, true );
	$now    = pllx_hash( pllx_post_payload( $source_id ) );
	if ( '' === $stored ) {
		$warnings[] = "post $target_id has no recorded source hash; staleness cannot be detected";
	} elseif ( $stored !== $now ) {
		$warnings[] = "post $target_id is stale: source $source_id changed since it was translated";
	}

	// 4. Not byte-identical to the source. A warning, never a failure: brand
	//    names and short labels are legitimately the same in both languages.
	$s = get_post( $source_id );
	$t = get_post( $target_id );
	if ( $s->post_title === $t->post_title && '' !== trim( $s->post_title ) ) {
		$warnings[] = "post $target_id has the same title as its source: '{$s->post_title}'";
	}

	// 6. Slug collisions. WordPress scopes uniqueness to post type and parent, so
	//    a page and a post may share a slug, and so may two children of different
	//    parents. Keying on the slug alone would report those as failures.
	$slug = $t->post_name;
	if ( '' !== $slug ) {
		$key = $t->post_type . '|' . (int) $t->post_parent . '|' . $slug;
		if ( isset( $seen_slugs[ $key ] ) ) {
			$failures[] = "slug '$slug' is used by both post $target_id and post {$seen_slugs[$key]} (same type and parent)";
		}
		$seen_slugs[ $key ] = $target_id;
	}
}

// 7. Orphans: target-language posts whose group points nowhere. $target_posts was
//    classified in the same pass above.
foreach ( $target_posts as $target_id ) {
	$group = pll_get_post_translations( $target_id );
	if ( ! empty( $group[ $source ] ) && ! get_post( (int) $group[ $source ] ) ) {
		$failures[] = "post $target_id is orphaned: its source {$group[$source]} no longer exists";
	}
}

// ── 8. Terms ────────────────────────────────────────────────────────────────
foreach ( array_keys( PLL()->model->get_translated_taxonomies() ) as $taxonomy ) {
	// Same reasoning as for posts: no 'lang' filter, classify explicitly.
	$terms = get_terms( array( 'taxonomy' => $taxonomy, 'hide_empty' => false ) );
	if ( is_wp_error( $terms ) ) {
		continue;
	}
	foreach ( $terms as $term ) {
		$term_lang = pll_get_term_language( $term->term_id );
		if ( ! $term_lang ) {
			$unassigned[ $taxonomy ] = isset( $unassigned[ $taxonomy ] ) ? $unassigned[ $taxonomy ] + 1 : 1;
			continue;
		}
		if ( $term_lang !== $source ) {
			continue;
		}
		$counts['terms']++;
		$translations = pll_get_term_translations( $term->term_id );

		if ( empty( $translations[ $target ] ) ) {
			$failures[] = "term {$term->term_id} ('{$term->name}', $taxonomy) has no $target counterpart";
			continue;
		}

		$target_id = (int) $translations[ $target ];
		$actual    = pll_get_term_language( $target_id );
		if ( $actual !== $target ) {
			$failures[] = "term $target_id has language '" . ( $actual ? $actual : 'none' ) . "', expected '$target'";
		}

		$stored = get_term_meta( $target_id, PLLX_HASH_META, true );
		$now    = pllx_hash( pllx_term_payload( $term->term_id, $taxonomy ) );
		if ( '' === $stored ) {
			$warnings[] = "term $target_id has no recorded source hash; staleness cannot be detected";
		} elseif ( $stored !== $now ) {
			$warnings[] = "term $target_id is stale: source {$term->term_id} changed since it was translated";
		}
	}
}

// ── 9. Internal links inside translated content point at translated targets ─
//
// Same defect as check 1 (menu items), same severity, in a different store:
// a same-host href inside a target-language post's content that resolves to
// a post must resolve to a post IN THE TARGET LANGUAGE. A hard failure, not
// a warning -- pll-import.php's link-rewrite pass exists to make this true,
// so a failure here means that pass missed something or ran on a site whose
// content was hand-edited afterwards. $target_posts was classified above,
// in the same pass as $source_posts.
foreach ( $target_posts as $target_id ) {
	$content = get_post_field( 'post_content', $target_id );
	if ( ! is_string( $content ) || false === strpos( $content, 'href=' ) ) {
		continue;
	}
	if ( ! preg_match_all( '/href=(["\'])([^"\']+)\1/', $content, $m ) ) {
		continue;
	}
	foreach ( $m[2] as $href ) {
		$found_id = pllx_url_to_postid( $href );
		if ( ! $found_id ) {
			continue; // external, or not a post URL -- nothing to check.
		}
		$counts['internal_links']++;
		$lang = pll_get_post_language( $found_id );
		if ( $lang !== $target ) {
			$failures[] = "post $target_id links to a '" . ( $lang ? $lang : 'none' ) . "' post ($found_id) via an internal href, expected '$target'";
		}
	}
}

// ── Report ──────────────────────────────────────────────────────────────────
// Machine-readable so the live suite can assert on the numbers rather than on
// the mere exit code. An audit that examined nothing must not report success.
pllx_info( sprintf(
	'Audited posts=%d terms=%d menu_items=%d internal_links=%d unassigned=%d for %s -> %s',
	$counts['posts'], $counts['terms'], $counts['menu_items'], $counts['internal_links'], array_sum( $unassigned ), $source, $target
) );

$unassigned_total = array_sum( $unassigned );
if ( $unassigned_total > 0 ) {
	foreach ( $unassigned as $type => $count ) {
		$warnings[] = "$count object(s) of type '$type' have no language assigned and were not audited";
	}
}

foreach ( $warnings as $w ) {
	pllx_warn( $w );
}

// A verifier that finds nothing to verify has not verified anything. Reporting
// PASS there is the same defect class as an assertion that counts zero and
// still succeeds, so it is a hard failure, not a warning.
if ( 0 === $counts['posts'] && 0 === $counts['terms'] ) {
	$failures[] = "nothing to audit: no '$source' posts and no '$source' terms found";
}

if ( $failures ) {
	foreach ( $failures as $f ) {
		fwrite( STDERR, "[x] $f\n" );
	}
	pllx_fail( sprintf( '%d failure(s), %d warning(s).', count( $failures ), count( $warnings ) ) );
}

pllx_info( sprintf( 'PASS — 0 failures, %d warning(s).', count( $warnings ) ) );
