"use client";

import { createContext, useContext, useEffect, useRef, type ReactNode } from "react";
import { intlLocales, setRuntimeLocale, translateUiText } from "@/lib/i18n";
import type { Locale } from "@/lib/types";

type TextState = { source: string; translated: string };
type AttributeState = Partial<Record<"placeholder" | "title" | "aria-label", TextState>>;

const ignoredTags = new Set(["SCRIPT", "STYLE", "CODE", "PRE"]);
const LocaleContext = createContext<Locale>("tr");

export function useAppLocale() {
  return useContext(LocaleContext);
}

function localizeRoot(root: HTMLElement, locale: Locale, textStates: WeakMap<Text, TextState>, attributeStates: WeakMap<Element, AttributeState>) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let current = walker.nextNode();
  while (current) {
    const node = current as Text;
    const parent = node.parentElement;
    if (parent && !ignoredTags.has(parent.tagName) && !parent.closest("[data-no-translate='true']")) {
      const existing = textStates.get(node);
      const currentText = node.nodeValue || "";
      const source = existing && currentText === existing.translated ? existing.source : currentText;
      const translated = translateUiText(source, locale);
      textStates.set(node, { source, translated });
      if (currentText !== translated) node.nodeValue = translated;
    }
    current = walker.nextNode();
  }

  const elements = [root, ...Array.from(root.querySelectorAll("[placeholder], [title], [aria-label]"))];
  for (const element of elements) {
    if (element.closest("[data-no-translate='true']")) continue;
    const state = attributeStates.get(element) || {};
    for (const attribute of ["placeholder", "title", "aria-label"] as const) {
      const currentValue = element.getAttribute(attribute);
      if (!currentValue) continue;
      const existing = state[attribute];
      const source = existing && currentValue === existing.translated ? existing.source : currentValue;
      const translated = translateUiText(source, locale);
      state[attribute] = { source, translated };
      if (currentValue !== translated) element.setAttribute(attribute, translated);
    }
    attributeStates.set(element, state);
  }
}

export function LocalizedContent({ locale, children, className }: { locale: Locale; children: ReactNode; className?: string }) {
  setRuntimeLocale(locale);
  const rootRef = useRef<HTMLDivElement>(null);
  const textStates = useRef(new WeakMap<Text, TextState>());
  const attributeStates = useRef(new WeakMap<Element, AttributeState>());

  useEffect(() => {
    document.documentElement.lang = locale;
    document.documentElement.dataset.locale = locale;
    window.localStorage.setItem("nutriclinic_locale", locale);
    const root = rootRef.current;
    if (!root) return;

    let scheduled = false;
    const translate = () => {
      scheduled = false;
      const textStateMap = textStates.current;
      const attributeStateMap = attributeStates.current;
      if (!textStateMap || !attributeStateMap) return;
      localizeRoot(root, locale, textStateMap, attributeStateMap);
    };
    const schedule = () => {
      if (scheduled) return;
      scheduled = true;
      window.requestAnimationFrame(translate);
    };

    translate();
    const observer = new MutationObserver(schedule);
    observer.observe(root, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["placeholder", "title", "aria-label"] });
    return () => observer.disconnect();
  }, [locale]);

  return <LocaleContext.Provider value={locale}><div ref={rootRef} className={className} data-locale={locale}>{children}</div></LocaleContext.Provider>;
}

export function formatDate(value: string | Date | null | undefined, locale: Locale, options?: Intl.DateTimeFormatOptions) {
  if (!value) return "—";
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat(intlLocales[locale], options || { dateStyle: "medium" }).format(date);
}

export function formatDateTime(value: string | Date | null | undefined, locale: Locale) {
  return formatDate(value, locale, { dateStyle: "medium", timeStyle: "short" });
}

export function formatMoney(value: number | null | undefined, locale: Locale, currency = "TRY") {
  return new Intl.NumberFormat(intlLocales[locale], { style: "currency", currency, maximumFractionDigits: 2 }).format(Number(value || 0));
}
