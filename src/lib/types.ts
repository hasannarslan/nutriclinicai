export type Role = "owner" | "dietitian" | "secretary" | "client";
export type Locale = "tr" | "en" | "el" | "ru" | "de";

export type Profile = {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  preferred_locale: Locale;
};

export type Membership = {
  id: string;
  clinic_id: string;
  user_id: string;
  role: Role;
  is_active: boolean;
};

export type Clinic = {
  id: string;
  name: string;
  slug: string;
  default_locale: Locale;
  timezone: string;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  website?: string | null;
  booking_horizon_days?: number;
  minimum_booking_notice_hours?: number;
  cancellation_notice_hours?: number;
  allow_client_cancellation?: boolean;
  allow_online_booking?: boolean;
};
