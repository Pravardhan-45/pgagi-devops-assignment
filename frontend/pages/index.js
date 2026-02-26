import { useState, useEffect } from 'react';
import Head from 'next/head';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';

export default function Home() {
    const [health, setHealth] = useState(null);
    const [message, setMessage] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        async function fetchData() {
            try {
                setLoading(true);
                setError(null);

                const [healthRes, messageRes] = await Promise.all([
                    fetch(`${API_URL}/api/health`),
                    fetch(`${API_URL}/api/message`),
                ]);

                if (!healthRes.ok || !messageRes.ok) {
                    throw new Error('Backend responded with an error');
                }

                const healthData = await healthRes.json();
                const messageData = await messageRes.json();

                setHealth(healthData);
                setMessage(messageData);
            } catch (err) {
                setError(err.message || 'Failed to connect to backend');
            } finally {
                setLoading(false);
            }
        }

        fetchData();
    }, []);

    return (
        <>
            <Head>
                <title>DevOps Assignment – PGAGI</title>
                <meta name="description" content="PGAGI DevOps Assignment - FastAPI + Next.js deployed on AWS and GCP" />
                <link rel="preconnect" href="https://fonts.googleapis.com" />
                <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="true" />
                <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet" />
            </Head>

            <main style={styles.main}>
                {/* Animated gradient background */}
                <div style={styles.bgGradient} />
                <div style={styles.bgOrb1} />
                <div style={styles.bgOrb2} />

                <div style={styles.container}>
                    {/* Header */}
                    <div style={styles.header}>
                        <div style={styles.badge}>🚀 PGAGI DevOps Assignment</div>
                        <h1 style={styles.title}>
                            Cloud Infrastructure
                            <span style={styles.titleGradient}> Demo</span>
                        </h1>
                        <p style={styles.subtitle}>
                            FastAPI backend · Next.js frontend · AWS + GCP deployment
                        </p>
                    </div>

                    {/* Status Cards */}
                    <div style={styles.grid}>
                        {/* Backend Status Card */}
                        <div style={styles.card}>
                            <div style={styles.cardHeader}>
                                <div style={{
                                    ...styles.statusDot,
                                    backgroundColor: loading ? '#f59e0b' : error ? '#ef4444' : '#10b981'
                                }} />
                                <h2 style={styles.cardTitle}>Backend Status</h2>
                            </div>

                            {loading && (
                                <div style={styles.loading}>
                                    <div style={styles.spinner} />
                                    <span>Connecting to backend...</span>
                                </div>
                            )}

                            {error && (
                                <div style={styles.errorBox}>
                                    <span style={styles.errorIcon}>⚠️</span>
                                    <div>
                                        <p style={styles.errorTitle}>Connection Failed</p>
                                        <p style={styles.errorMsg}>{error}</p>
                                    </div>
                                </div>
                            )}

                            {health && !loading && (
                                <div style={styles.successBox}>
                                    <div style={styles.successRow}>
                                        <span style={styles.label}>Status</span>
                                        <span style={styles.valuePill}>{health.status}</span>
                                    </div>
                                    <div style={styles.successRow}>
                                        <span style={styles.label}>Message</span>
                                        <span style={styles.value}>{health.message}</span>
                                    </div>
                                </div>
                            )}
                        </div>

                        {/* Backend Message Card */}
                        <div style={styles.card}>
                            <div style={styles.cardHeader}>
                                <span style={styles.cardIcon}>💬</span>
                                <h2 style={styles.cardTitle}>Integration Message</h2>
                            </div>

                            {loading && (
                                <div style={styles.loading}>
                                    <div style={styles.spinner} />
                                    <span>Fetching message...</span>
                                </div>
                            )}

                            {message && !loading && (
                                <div style={styles.messageBox}>
                                    <p style={styles.messageText}>"{message.message}"</p>
                                </div>
                            )}

                            {error && !loading && (
                                <p style={styles.errorMsg}>Could not fetch message.</p>
                            )}
                        </div>

                        {/* Deployment Info Card */}
                        <div style={{ ...styles.card, gridColumn: 'span 2' }}>
                            <div style={styles.cardHeader}>
                                <span style={styles.cardIcon}>☁️</span>
                                <h2 style={styles.cardTitle}>Deployment Info</h2>
                            </div>
                            <div style={styles.infoGrid}>
                                <div style={styles.infoItem}>
                                    <span style={styles.infoLabel}>Backend URL</span>
                                    <code style={styles.infoValue}>{API_URL}</code>
                                </div>
                                <div style={styles.infoItem}>
                                    <span style={styles.infoLabel}>AWS Region</span>
                                    <code style={styles.infoValue}>ap-south-1 (Mumbai)</code>
                                </div>
                                <div style={styles.infoItem}>
                                    <span style={styles.infoLabel}>GCP Region</span>
                                    <code style={styles.infoValue}>asia-south1 (Mumbai)</code>
                                </div>
                                <div style={styles.infoItem}>
                                    <span style={styles.infoLabel}>IaC Tool</span>
                                    <code style={styles.infoValue}>Terraform</code>
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* Footer */}
                    <p style={styles.footer}>
                        Deployed with ❤️ by Pravardhan Aare · Pravardhan-45/pgagi-devops-assignment
                    </p>
                </div>
            </main>
        </>
    );
}

const styles = {
    main: {
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#0a0a0f',
        fontFamily: "'Inter', -apple-system, sans-serif",
        position: 'relative',
        overflow: 'hidden',
        padding: '2rem',
    },
    bgGradient: {
        position: 'fixed',
        inset: 0,
        background: 'radial-gradient(ellipse 80% 80% at 50% -20%, rgba(120,58,237,0.3), transparent)',
        pointerEvents: 'none',
    },
    bgOrb1: {
        position: 'fixed',
        width: '600px',
        height: '600px',
        borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(59,130,246,0.15), transparent 70%)',
        top: '-200px',
        right: '-100px',
        pointerEvents: 'none',
    },
    bgOrb2: {
        position: 'fixed',
        width: '400px',
        height: '400px',
        borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(16,185,129,0.1), transparent 70%)',
        bottom: '-100px',
        left: '-100px',
        pointerEvents: 'none',
    },
    container: {
        width: '100%',
        maxWidth: '900px',
        position: 'relative',
        zIndex: 1,
    },
    header: {
        textAlign: 'center',
        marginBottom: '3rem',
    },
    badge: {
        display: 'inline-block',
        background: 'rgba(120,58,237,0.2)',
        border: '1px solid rgba(120,58,237,0.4)',
        color: '#a78bfa',
        padding: '0.4rem 1rem',
        borderRadius: '999px',
        fontSize: '0.85rem',
        fontWeight: 500,
        marginBottom: '1.5rem',
        letterSpacing: '0.02em',
    },
    title: {
        fontSize: 'clamp(2rem, 5vw, 3.5rem)',
        fontWeight: 700,
        color: '#f1f5f9',
        margin: '0 0 1rem',
        lineHeight: 1.1,
        letterSpacing: '-0.02em',
    },
    titleGradient: {
        background: 'linear-gradient(135deg, #7c3aed, #3b82f6, #10b981)',
        WebkitBackgroundClip: 'text',
        WebkitTextFillColor: 'transparent',
        backgroundClip: 'text',
    },
    subtitle: {
        color: '#64748b',
        fontSize: '1.1rem',
        margin: 0,
        fontWeight: 400,
    },
    grid: {
        display: 'grid',
        gridTemplateColumns: '1fr 1fr',
        gap: '1.5rem',
        marginBottom: '2rem',
    },
    card: {
        background: 'rgba(15,23,42,0.8)',
        border: '1px solid rgba(148,163,184,0.1)',
        borderRadius: '16px',
        padding: '1.75rem',
        backdropFilter: 'blur(12px)',
        boxShadow: '0 4px 24px rgba(0,0,0,0.4)',
        transition: 'border-color 0.2s, transform 0.2s',
    },
    cardHeader: {
        display: 'flex',
        alignItems: 'center',
        gap: '0.75rem',
        marginBottom: '1.25rem',
    },
    cardTitle: {
        color: '#e2e8f0',
        fontSize: '1rem',
        fontWeight: 600,
        margin: 0,
    },
    cardIcon: {
        fontSize: '1.25rem',
    },
    statusDot: {
        width: '10px',
        height: '10px',
        borderRadius: '50%',
        flexShrink: 0,
    },
    loading: {
        display: 'flex',
        alignItems: 'center',
        gap: '0.75rem',
        color: '#64748b',
        fontSize: '0.9rem',
    },
    spinner: {
        width: '18px',
        height: '18px',
        border: '2px solid rgba(100,116,139,0.3)',
        borderTopColor: '#7c3aed',
        borderRadius: '50%',
        animation: 'spin 0.8s linear infinite',
    },
    errorBox: {
        display: 'flex',
        gap: '0.75rem',
        background: 'rgba(239,68,68,0.1)',
        border: '1px solid rgba(239,68,68,0.2)',
        borderRadius: '8px',
        padding: '1rem',
    },
    errorIcon: { fontSize: '1.25rem' },
    errorTitle: { color: '#f87171', fontWeight: 600, margin: '0 0 0.25rem', fontSize: '0.9rem' },
    errorMsg: { color: '#94a3b8', margin: 0, fontSize: '0.85rem' },
    successBox: {
        display: 'flex',
        flexDirection: 'column',
        gap: '0.75rem',
    },
    successRow: {
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        gap: '1rem',
    },
    label: {
        color: '#64748b',
        fontSize: '0.85rem',
        fontWeight: 500,
    },
    value: {
        color: '#cbd5e1',
        fontSize: '0.85rem',
        textAlign: 'right',
    },
    valuePill: {
        background: 'rgba(16,185,129,0.15)',
        color: '#34d399',
        padding: '0.2rem 0.6rem',
        borderRadius: '999px',
        fontSize: '0.8rem',
        fontWeight: 600,
        textTransform: 'capitalize',
    },
    messageBox: {
        background: 'rgba(120,58,237,0.1)',
        border: '1px solid rgba(120,58,237,0.2)',
        borderRadius: '10px',
        padding: '1.25rem',
    },
    messageText: {
        color: '#c4b5fd',
        fontSize: '1rem',
        fontWeight: 500,
        margin: 0,
        lineHeight: 1.6,
        fontStyle: 'italic',
    },
    infoGrid: {
        display: 'grid',
        gridTemplateColumns: '1fr 1fr',
        gap: '1rem',
    },
    infoItem: {
        display: 'flex',
        flexDirection: 'column',
        gap: '0.35rem',
    },
    infoLabel: {
        color: '#475569',
        fontSize: '0.78rem',
        fontWeight: 500,
        textTransform: 'uppercase',
        letterSpacing: '0.05em',
    },
    infoValue: {
        color: '#94a3b8',
        fontSize: '0.88rem',
        fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
        background: 'rgba(148,163,184,0.08)',
        padding: '0.3rem 0.6rem',
        borderRadius: '6px',
    },
    footer: {
        textAlign: 'center',
        color: '#334155',
        fontSize: '0.85rem',
        marginTop: '1rem',
    },
};
