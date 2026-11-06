"""
Coastal Care analytics dashboard (Streamlit, open source).   DASH-1

HIPAA by construction: right after connecting, the session runs SET ROLE cc_analyst, so
this app can read ONLY the de-identified gold schema, even when started by the database
owner. A query against silver, mpi or bronze fails with "permission denied".

Run from the project root:   streamlit run dashboard/app.py
"""
from __future__ import annotations

import os

import altair as alt
import pandas as pd
import psycopg2
import streamlit as st
from dotenv import load_dotenv

# Fixed colour per line of business (validated categorical order; colour follows the entity,
# never its rank, so filtering never repaints a series).
LOB_COLORS = {"MEDICARE": "#2a78d6", "MEDICAID": "#eb6834", "COMMERCIAL": "#1baf7a",
              "DUAL": "#eda100", "SELF_PAY": "#e87ba4"}
INK, MUTED = "#52514e", "#898781"

st.set_page_config(page_title="Coastal Care Analytics", layout="wide")


@st.cache_resource
def connect():
    load_dotenv()
    conn = psycopg2.connect(host=os.getenv("PG_HOST", "localhost"), port=os.getenv("PG_PORT", "5432"),
                            dbname=os.getenv("PG_DB", "coastal_care"), user=os.getenv("PG_USER") or None,
                            password=os.getenv("PG_PASSWORD") or None)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SET ROLE cc_analyst")          # minimum necessary: gold only
    return conn


@st.cache_data(ttl=300)
def q(sql: str) -> pd.DataFrame:
    with connect().cursor() as cur:
        cur.execute(sql)
        return pd.DataFrame(cur.fetchall(), columns=[c.name for c in cur.description])


def lob_color(domain):
    return alt.Color("line_of_business:N", title="Line of business",
                     scale=alt.Scale(domain=list(domain), range=[LOB_COLORS[d] for d in domain]))


def axis_style(chart):
    return (chart.configure_axis(labelColor=MUTED, titleColor=INK, gridColor="#e6e5e0", domainColor="#d0cfca")
                 .configure_legend(labelColor=INK, titleColor=INK).configure_view(stroke=None))


st.title("Coastal Care Analytics")
st.caption("Gold layer only (role cc_analyst). Synthetic data: CMS DE-SynPUF and Synthea.")

sources = q("select distinct source_system from gold.fct_claim order by 1")["source_system"].tolist()
c1, c2 = st.columns([2, 3])
src = c1.multiselect("Source", sources, default=sources)
if not src:
    st.stop()
in_src = "(" + ",".join("'" + s.replace("'", "") + "'" for s in src) + ")"

kpi = q(f"""select (select count(distinct member_key) from gold.fct_claim where source_system in {in_src}) as members,
                   (select count(*) from gold.fct_claim where source_system in {in_src}) as claims,
                   (select coalesce(sum(paid_amount), 0) from gold.fct_claim where source_system in {in_src}) as paid,
                   (select round(100.0 * avg(is_readmitted_30d::int), 1) from gold.mart_readmission_30d
                     where source_system in {in_src}) as readmit""").iloc[0]
k = st.columns(4)
k[0].metric("Members with claims", f"{int(kpi.members):,}")
k[1].metric("Claims", f"{int(kpi.claims):,}")
k[2].metric("Net paid", f"${float(kpi.paid):,.0f}")
k[3].metric("30-day readmission rate", "n/a" if kpi.readmit is None else f"{float(kpi.readmit):.1f}%")

left, right = st.columns(2)
with left:
    st.subheader("Cost per member per month (PMPM)")
    pmpm = q(f"""select year, line_of_business, sum(paid_amount) / nullif(max(member_months), 0) as pmpm
                 from gold.mart_pmpm where source_system in {in_src} and member_months > 0
                 group by 1, 2 order by 1""")
    if pmpm.empty:
        st.info("No enrolled member months for this selection (Synthea enrollment arrives with the 834).")
    else:
        pmpm["pmpm"] = pmpm["pmpm"].astype(float)
        chart = alt.Chart(pmpm).mark_line(point=alt.OverlayMarkDef(size=64, filled=True), strokeWidth=2).encode(
            x=alt.X("year:O", title="Year", axis=alt.Axis(labelAngle=0)), y=alt.Y("pmpm:Q", title="PMPM ($)"),
            color=lob_color(sorted(pmpm.line_of_business.unique())),
            tooltip=[alt.Tooltip("year:O"), "line_of_business", alt.Tooltip("pmpm:Q", format="$,.2f")])
        st.altair_chart(axis_style(chart), use_container_width=True)
        st.caption("Net paid (incl. recoupments) / member months with any medical coverage.")

with right:
    st.subheader("Net paid by claim type")
    by_type = q(f"""select claim_type, line_of_business, sum(paid_amount) as paid from gold.fct_claim
                    where source_system in {in_src} group by 1, 2""")
    by_type["paid"] = by_type["paid"].astype(float)
    chart = alt.Chart(by_type).mark_bar(cornerRadiusEnd=4, size=22).encode(
        y=alt.Y("claim_type:N", title=None, sort="-x"), x=alt.X("sum(paid):Q", title="Net paid ($)"),
        color=lob_color(sorted(by_type.line_of_business.unique())),
        tooltip=["claim_type", "line_of_business", alt.Tooltip("paid:Q", format="$,.2f")])
    st.altair_chart(axis_style(chart), use_container_width=True)

left, right = st.columns(2)
with left:
    st.subheader("30-day readmission rate")
    rr = q(f"""select discharge_year, sum(index_stays) as stays, sum(readmissions) as readmits
               from gold.mart_readmission_rate where source_system in {in_src} group by 1 order by 1""")
    if rr.empty:
        st.info("No index stays for this selection.")
    else:
        rr["rate"] = 100.0 * rr["readmits"].astype(float) / rr["stays"].astype(float)
        chart = alt.Chart(rr).mark_bar(cornerRadiusEnd=4, size=20, color="#2a78d6").encode(
            x=alt.X("discharge_year:O", title="Discharge year", axis=alt.Axis(labelAngle=0)), y=alt.Y("rate:Q", title="Readmitted within 30 days (%)"),
            tooltip=["discharge_year", "stays", "readmits", alt.Tooltip("rate:Q", format=".1f")])
        st.altair_chart(axis_style(chart), use_container_width=True)
        st.caption("All-cause; index stays discharged alive with 30 days of follow-up. Planned readmissions not excluded yet.")

with right:
    st.subheader("837P submission readiness")
    ready = q("select status, sum(claims) as claims, sum(billed_amount) as billed from gold.mart_edi_readiness group by 1")
    ready["claims"] = ready["claims"].astype(int)
    chart = alt.Chart(ready).mark_bar(cornerRadiusEnd=4, size=18, color="#2a78d6").encode(
        y=alt.Y("status:N", title=None, sort="-x"), x=alt.X("claims:Q", title="Claims", axis=alt.Axis(format="d", tickMinStep=1)),
        tooltip=["status", "claims", alt.Tooltip("billed:Q", format="$,.2f")])
    st.altair_chart(axis_style(chart), use_container_width=True)
    st.caption("READY claims are sent as 837P; the rest are held by the first failing pre-submission edit.")

st.subheader("Data quality scorecard")
dq = q("select metric, scope, value from gold.mart_data_quality order by metric")
st.dataframe(dq, hide_index=True, width="stretch")

with st.expander("Data tables (for screen readers and export)"):
    st.dataframe(q(f"select * from gold.mart_pmpm where source_system in {in_src} order by 1, 2, 3, 4"), hide_index=True)
    st.dataframe(q(f"select * from gold.mart_readmission_rate where source_system in {in_src} order by 1, 2, 3"), hide_index=True)
