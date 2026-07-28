#!/usr/bin/env node
// Logique pure du picker de zones admin (sélection / navigation) — testable
// hors navigateur. Doit rester alignée avec admin/index.html (afSelect /
// afClearSelection sur navigate).
"use strict";

function createFolderSelection() {
  let sel = null;
  return {
    get() { return sel; },
    select(id, name, path) {
      if (!id) return sel;
      sel = { id: String(id), name: String(name || ""), path: path ? String(path) : "" };
      return sel;
    },
    clear() { sel = null; return sel; },
    /** Naviguer (ouvrir dossier, fil d'Ariane, enter depuis search) efface la sélection. */
    onNavigate() { sel = null; return sel; },
  };
}

/**
 * Machine à états du flux authorize — capture le bug « fermer le picker
 * reprend Zones avant Valider ».
 * États : idle | picker | authorize | zones
 */
function createAuthorizeFlow() {
  let state = "idle";
  let pickerOpen = false;
  let authorizeOpen = false;
  let zonesOpen = false;
  let resumeZones = false;

  return {
    snapshot() {
      return { state, pickerOpen, authorizeOpen, zonesOpen, resumeZones };
    },
    openZones() {
      zonesOpen = true;
      state = "zones";
    },
    openPickerFromZones() {
      resumeZones = zonesOpen;
      zonesOpen = false;
      pickerOpen = true;
      state = "picker";
    },
    /** Sélectionner / ouvrir durée : NE PAS fermer le picker (sinon Zones revient). */
    openAuthorize() {
      if (!pickerOpen) return false;
      authorizeOpen = true;
      state = "authorize";
      return true;
    },
    /** Mauvaise implémentation historique : fermer le picker pour ouvrir authorize. */
    openAuthorizeByClosingPicker() {
      if (!pickerOpen) return false;
      pickerOpen = false;
      if (resumeZones) {
        zonesOpen = true;
        resumeZones = false;
        state = "zones";
      }
      authorizeOpen = true;
      // Zones déjà rouvertes → l'utilisateur croit que c'est fini, rien n'est ajouté.
      return { authorizeOpen, zonesOpen, pickerOpen, state };
    },
    cancelAuthorize() {
      authorizeOpen = false;
      state = pickerOpen ? "picker" : state;
    },
    confirmSuccess() {
      authorizeOpen = false;
      pickerOpen = false;
      if (resumeZones) {
        zonesOpen = true;
        resumeZones = false;
      }
      state = zonesOpen ? "zones" : "idle";
    },
  };
}

module.exports = { createFolderSelection, createAuthorizeFlow };

if (require.main === module) {
  const assert = (cond, msg) => { if (!cond) { console.error("FAIL", msg); process.exit(1); } };
  const sel = createFolderSelection();
  sel.select("FOLDERID123456789012", "paroi", "CLIENTS/paroi");
  assert(sel.get() && sel.get().name === "paroi", "select keeps folder");
  sel.onNavigate();
  assert(sel.get() === null, "navigate clears selection");
  sel.select("FOLDERID123456789012", "paroi");
  sel.clear();
  assert(sel.get() === null, "clear empties selection");

  const bad = createAuthorizeFlow();
  bad.openZones();
  bad.openPickerFromZones();
  const leaked = bad.openAuthorizeByClosingPicker();
  assert(leaked.zonesOpen === true && leaked.pickerOpen === false, "bug: closing picker resumes zones");

  const good = createAuthorizeFlow();
  good.openZones();
  good.openPickerFromZones();
  assert(good.openAuthorize() === true, "authorize opens on top of picker");
  let s = good.snapshot();
  assert(s.pickerOpen && s.authorizeOpen && !s.zonesOpen, "picker stays open under authorize");
  good.confirmSuccess();
  s = good.snapshot();
  assert(s.zonesOpen && !s.pickerOpen && !s.authorizeOpen, "success returns to zones");
  console.log("ok");
}
