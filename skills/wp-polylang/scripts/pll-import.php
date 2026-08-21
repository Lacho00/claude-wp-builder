<?php
/**
 * Write a translated manifest back through the Polylang API.
 *
 * Usage: wp eval-file pll-import.php <translated.json>
 *
 * The whole file is validated before the first write. Counterparts are created
 * published, mirroring the source status, so writing half of them and finding
 * the problem at item 30 is not acceptable.
 *
 * No rollback is needed on a mid-run failure: hashes are recorded only after a
 * successful write, so re-running resumes where it stopped.
 */

require_once __DIR__ . '/pll-lib.php';

list( $manifest_path ) = pllx_args( 1, 'pll-import.php <translated.json>' );

pllx_require_polylang();

if ( ! is_readable( $manifest_path ) ) {
	pllx_fail( "Cannot read manifest '$manifest_path'." );
}

$manifest = json_decode( file_get_contents( $manifest_path ), true );
if ( ! is_array( $manifest ) ) {
	pllx_fail( 'Manifest is not valid JSON: ' . json_last_error_msg() );
}

foreach ( array( 'source_lang', 'target_lang', 'items' ) as $key ) {
	if ( ! isset( $manifest[ $key ] ) ) {
		pllx_fail( "Manifest is missing '$key'." );
	}
}

$source = $manifest['source_lang'];
$target = $manifest['target_lang'];
pllx_require_langs( $source, $target );

// ── Validate every item before writing anything ─────────────────────────────
$errors = array();
foreach ( $manifest['items'] as $i => $item ) {
	foreach ( array( 'id', 'kind', 'hash', 'fields' ) as $key ) {
		if ( ! isset( $item[ $key ] ) ) {
			$errors[] = "item $i is missing '$key'";
		}
	}
	if ( isset( $item['kind'] ) && ! in_array( $item['kind'], array( 'post', 'term', 'string' ), true ) ) {
		$errors[] = "item $i has unknown kind '{$item['kind']}'";
	}
	if ( isset( $item['fields'] ) && ! is_array( $item['fields'] ) ) {
		$errors[] = "item $i has a non-object 'fields'";
	}
	if ( isset( $item['kind'] ) && 'post' === $item['kind'] ) {
		if ( empty( $item['source_id'] ) || ! get_post( $item['source_id'] ) ) {
			$errors[] = "item $i references post {$item['source_id']}, which does not exist";
		}
	}
	if ( isset( $item['kind'] ) && 'term' === $item['kind'] ) {
		if ( empty( $item['taxonomy'] ) || empty( $item['source_id'] )
			|| is_wp_error( get_term( $item['source_id'], $item['taxonomy'] ) ) ) {
			$errors[] = "item $i references a term that does not exist";
		}
	}
}

if ( $errors ) {
	foreach ( $errors as $e ) {
		pllx_warn( $e );
	}
	pllx_fail( sprintf( '%d validation error(s); nothing was written.', count( $errors ) ) );
}

// ── Write ───────────────────────────────────────────────────────────────────
$written        = 0;
$written_posts   = 0;
$written_attach  = 0;
$written_terms   = 0;
$written_strings = 0;

// source_id => target_id, for posts written this run. Used by the parent-fixup
// pass below. Export order is not parent-first, so a parent's counterpart may
// not exist yet when its child is written -- this map lets the fixup pass run
// after every post has its counterpart.
$post_counterparts = array();

foreach ( $manifest['items'] as $item ) {
	if ( 'post' === $item['kind'] ) {
		$source_id   = (int) $item['source_id'];
		$source_post = get_post( $source_id );
		$fields      = $item['fields'];
		$is_attachment = 'attachment' === $source_post->post_type;

		if ( $is_attachment ) {
			$existing_target_id = ( ! empty( $item['target_id'] ) && get_post( $item['target_id'] ) )
				? (int) $item['target_id']
				: 0;

			if ( $existing_target_id ) {
				// The counterpart already exists (a prior run created it via
				// create_media_translation()); only the translated text needs
				// updating, so a plain wp_update_post() is enough here.
				$target_id = $existing_target_id;
			} else {
				// Attachments need Polylang's own duplication path, not
				// wp_insert_post: create_media_translation() copies the
				// attachment metadata and _wp_attached_file, without which the
				// counterpart is broken media pointing at no file. It also
				// sets the language and joins the translation group itself, so
				// those two steps below are skipped for this branch.
				$target_id = PLL()->model->post->create_media_translation( $source_id, $target );

				if ( empty( $target_id ) ) {
					pllx_warn( "attachment $source_id: create_media_translation() failed" );
					continue;
				}
			}

			$update = array( 'ID' => $target_id );
			if ( isset( $fields['post_title'] ) ) {
				$update['post_title'] = $fields['post_title'];
			}
			if ( isset( $fields['post_content'] ) ) {
				$update['post_content'] = $fields['post_content'];
			}
			if ( isset( $fields['post_excerpt'] ) ) {
				$update['post_excerpt'] = $fields['post_excerpt'];
			}
			$res = wp_update_post( $update, true );
			if ( is_wp_error( $res ) ) {
				pllx_warn( "attachment $source_id -> $target_id: " . $res->get_error_message() );
				continue;
			}

			$post_counterparts[ $source_id ] = $target_id;
			update_post_meta( $target_id, PLLX_HASH_META, $item['hash'] );
			$written++;
			$written_attach++;
			pllx_info( "  attachment $source_id -> $target_id" );
			continue;
		}

		$postarr = array(
			'post_title'   => isset( $fields['post_title'] ) ? $fields['post_title'] : $source_post->post_title,
			'post_content' => isset( $fields['post_content'] ) ? $fields['post_content'] : '',
			'post_excerpt' => isset( $fields['post_excerpt'] ) ? $fields['post_excerpt'] : '',
			'post_name'    => isset( $fields['post_name'] ) ? sanitize_title( $fields['post_name'] ) : '',
			'post_type'    => $source_post->post_type,
			'post_status'  => $source_post->post_status,
			'post_parent'  => 0,
			'menu_order'   => $source_post->menu_order,
		);

		if ( ! empty( $item['target_id'] ) && get_post( $item['target_id'] ) ) {
			$postarr['ID'] = (int) $item['target_id'];
			$target_id     = wp_update_post( $postarr, true );
		} else {
			$target_id = wp_insert_post( $postarr, true );
		}

		if ( is_wp_error( $target_id ) ) {
			pllx_warn( "post $source_id: " . $target_id->get_error_message() );
			continue;
		}

		// Language first, then the complete group. pll_save_post_translations()
		// expects the whole group, not a delta.
		pll_set_post_language( $target_id, $target );
		pll_save_post_translations( array( $source => $source_id, $target => $target_id ) );

		// Non-text fields are copied verbatim; only text was translated.
		$thumb = get_post_thumbnail_id( $source_id );
		if ( $thumb ) {
			set_post_thumbnail( $target_id, $thumb );
		}

		if ( ! empty( $item['acf'] ) && function_exists( 'update_field' ) ) {
			foreach ( $item['acf'] as $dotted => $value ) {
				pllx_acf_write( $target_id, $dotted, $value );
			}
		}

		$post_counterparts[ $source_id ] = $target_id;
		update_post_meta( $target_id, PLLX_HASH_META, $item['hash'] );
		$written++;
		$written_posts++;
		pllx_info( "  post $source_id -> $target_id" );

	} elseif ( 'term' === $item['kind'] ) {
		$source_id = (int) $item['source_id'];
		$taxonomy  = $item['taxonomy'];
		$fields    = $item['fields'];
		$name      = isset( $fields['name'] ) ? $fields['name'] : '';
		$slug      = isset( $fields['slug'] ) ? sanitize_title( $fields['slug'] ) : '';

		if ( '' === $name ) {
			pllx_warn( "term $source_id has an empty name; skipping" );
			continue;
		}

		if ( ! empty( $item['target_id'] ) && ! is_wp_error( get_term( $item['target_id'], $taxonomy ) ) ) {
			$target_id = (int) $item['target_id'];
			$res       = wp_update_term( $target_id, $taxonomy, array(
				'name'        => $name,
				'slug'        => $slug,
				'description' => isset( $fields['description'] ) ? $fields['description'] : '',
			) );
		} else {
			$res = wp_insert_term( $name, $taxonomy, array(
				'slug'        => $slug,
				'description' => isset( $fields['description'] ) ? $fields['description'] : '',
			) );
		}

		if ( is_wp_error( $res ) ) {
			pllx_warn( "term $source_id: " . $res->get_error_message() );
			continue;
		}
		$target_id = (int) $res['term_id'];

		pll_set_term_language( $target_id, $target );
		pll_save_term_translations( array( $source => $source_id, $target => $target_id ) );

		update_term_meta( $target_id, PLLX_HASH_META, $item['hash'] );
		$written++;
		$written_terms++;
		pllx_info( "  term $source_id -> $target_id ($taxonomy)" );

	} elseif ( 'string' === $item['kind'] ) {
		$value = isset( $item['fields']['value'] ) ? $item['fields']['value'] : '';
		if ( '' === $value ) {
			continue;
		}
		pllx_string_translate( $item['id'], $value, $target );
		$written++;
		$written_strings++;
	}
}

// ── Parent fixup ──────────────────────────────────────────────────────────
//
// Every post above was written with post_parent = 0, since export order is
// not parent-first: a child can appear before its parent in the manifest, so
// there is no way to know the parent's counterpart id while writing the
// child inline. This second pass runs only after every post counterpart in
// this run exists, so it can look each one up.
$parents_fixed = 0;
foreach ( $post_counterparts as $source_id => $target_id ) {
	$source_post = get_post( $source_id );
	if ( ! $source_post || 0 === (int) $source_post->post_parent ) {
		continue;
	}

	$source_parent_id = (int) $source_post->post_parent;
	$parent_translations = pll_get_post_translations( $source_parent_id );

	if ( empty( $parent_translations[ $target ] ) ) {
		// Parent has no counterpart yet (not in this manifest, or not yet
		// translated). Nothing to point at; leave post_parent at 0 rather
		// than guess.
		continue;
	}

	$target_parent_id = (int) $parent_translations[ $target ];
	$res = wp_update_post( array(
		'ID'          => $target_id,
		'post_parent' => $target_parent_id,
	), true );

	if ( is_wp_error( $res ) ) {
		pllx_warn( "post $target_id: could not set post_parent to $target_parent_id: " . $res->get_error_message() );
		continue;
	}

	$parents_fixed++;
}

pllx_info( sprintf(
	'Wrote %d item(s): %d post(s), %d attachment(s), %d term(s), %d string(s).',
	$written,
	$written_posts,
	$written_attach,
	$written_terms,
	$written_strings
) );
pllx_info( sprintf( 'Fixed %d parent-child relationship(s).', $parents_fixed ) );

/**
 * Write one flattened ACF value back.
 *
 * Dot notation mirrors pllx_acf_walk(): `name`, `group.sub`, `repeater.0.sub`.
 */
function pllx_acf_write( $post_id, $dotted, $value ) {
	$parts = explode( '.', $dotted );

	if ( 1 === count( $parts ) ) {
		update_field( $parts[0], $value, $post_id );
		return;
	}

	if ( 2 === count( $parts ) ) {
		$group = get_field( $parts[0], $post_id );
		if ( ! is_array( $group ) ) {
			$group = array();
		}
		$group[ $parts[1] ] = $value;
		update_field( $parts[0], $group, $post_id );
		return;
	}

	if ( 3 === count( $parts ) ) {
		$rows = get_field( $parts[0], $post_id );
		if ( ! is_array( $rows ) ) {
			$rows = array();
		}
		$i = (int) $parts[1];
		if ( ! isset( $rows[ $i ] ) || ! is_array( $rows[ $i ] ) ) {
			$rows[ $i ] = array();
		}
		$rows[ $i ][ $parts[2] ] = $value;
		update_field( $parts[0], $rows, $post_id );
	}
}

/**
 * Store a string translation in Polylang's own option.
 *
 * Polylang keeps string translations in an MO object per language, saved under
 * a post of type `polylang_mo` whose id comes from PLL_MO::get_id().
 */
function pllx_string_translate( $item_id, $translated, $target ) {
	if ( ! class_exists( 'PLL_MO' ) ) {
		pllx_warn( 'PLL_MO is unavailable; skipping string translations.' );
		return;
	}

	// Recover the source text: the manifest id ends with md5(source), so match
	// against the registered strings rather than trying to reverse the hash.
	$source_text = null;
	if ( class_exists( 'PLL_Admin_Strings' ) ) {
		foreach ( PLL_Admin_Strings::get_strings() as $entry ) {
			$value   = isset( $entry['string'] ) ? $entry['string'] : '';
			$context = isset( $entry['context'] ) ? $entry['context'] : 'polylang';
			if ( 'string:' . $context . ':' . md5( $value ) === $item_id ) {
				$source_text = $value;
				break;
			}
		}
	}

	if ( null === $source_text ) {
		pllx_warn( "Could not match string item '$item_id' back to a registered string; skipping." );
		return;
	}

	$language = PLL()->model->get_language( $target );
	if ( ! $language ) {
		pllx_warn( "Unknown language '$target' while writing a string; skipping." );
		return;
	}

	$mo = new PLL_MO();
	$mo->import_from_db( $language );
	$mo->add_entry( $mo->make_entry( $source_text, $translated ) );
	$mo->export_to_db( $language );
}
