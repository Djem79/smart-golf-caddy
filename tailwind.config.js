/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: '#00450D',
        'primary-container': '#1B5E20',
        'on-primary': '#FFFFFF',
        'inverse-primary': '#91D78A',
        secondary: '#5E604D',
        'secondary-container': '#E1E1C9',
        'on-secondary': '#FFFFFF',
        tertiary: '#2D3D45',
        'tertiary-container': '#44545C',
        'on-tertiary': '#FFFFFF',
        surface: '#F9F9F9',
        'surface-dim': '#DADADA',
        'surface-container-lowest': '#FFFFFF',
        'surface-container-low': '#F3F3F4',
        'surface-container': '#EEEEEE',
        'surface-container-high': '#E8E8E8',
        'on-surface': '#1A1C1C',
        'on-surface-variant': '#41493E',
        outline: '#717A6D',
        'outline-variant': '#C0C9BB',
        error: '#BA1A1A',
        'error-container': '#FFDAD6',
        'on-error': '#FFFFFF',
      },
      fontFamily: {
        headline: ['"Playfair Display"', 'Georgia', 'serif'],
        body: ['Inter', 'sans-serif'],
      },
      fontSize: {
        'display-lg': ['40px', { lineHeight: '48px', letterSpacing: '-0.02em', fontWeight: '700' }],
        'headline-lg': ['32px', { lineHeight: '40px', letterSpacing: '-0.01em', fontWeight: '700' }],
        'headline-md': ['24px', { lineHeight: '32px', fontWeight: '600' }],
        'title-lg': ['20px', { lineHeight: '28px', fontWeight: '600' }],
        'body-md': ['16px', { lineHeight: '24px', fontWeight: '400' }],
        'label-lg': ['14px', { lineHeight: '20px', letterSpacing: '0.05em', fontWeight: '600' }],
        'label-md': ['12px', { lineHeight: '16px', fontWeight: '500' }],
      },
      borderRadius: {
        DEFAULT: '0.5rem',
        sm: '0.25rem',
        md: '0.75rem',
        lg: '1rem',
        xl: '1.5rem',
      },
      boxShadow: {
        card: '0px 1px 2px rgba(26, 28, 28, 0.04), 0px 4px 12px rgba(26, 28, 28, 0.04)',
        'card-hover': '0px 2px 4px rgba(26, 28, 28, 0.05), 0px 8px 24px rgba(26, 28, 28, 0.06)',
        elevated: '0px 1px 3px rgba(26, 28, 28, 0.06), 0px 12px 32px rgba(26, 28, 28, 0.08)',
      },
      transitionTimingFunction: {
        premium: 'cubic-bezier(0.32, 0.72, 0, 1)',
      },
      minHeight: {
        touch: '48px',
      },
      minWidth: {
        touch: '48px',
      },
    },
  },
  plugins: [],
}
